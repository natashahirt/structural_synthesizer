using System;
using System.Diagnostics;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Grasshopper.Kernel;
using Newtonsoft.Json.Linq;
using StructuralSizer.GH.Types;

namespace StructuralSizer.GH.Components
{
    /// <summary>
    /// Sends geometry + params to the Julia sizing API and returns the raw
    /// JSON response.
    ///
    /// Key UX features:
    ///   • Pre-flight /health check with clear "server not running" message
    ///   • Async background request — Grasshopper UI stays responsive
    ///   • Message bar shows current state: Ready, Computing…, ✓ 2.3 s, ✗ Error
    ///   • Smart caching: unchanged inputs return instantly
    ///   • Server-side geometry cache: param-only changes skip skeleton rebuild
    /// </summary>
    public class SizerRun : GH_Component
    {
        private static readonly HttpClient _client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(300)
        };

        // ─── Cached results ──────────────────────────────────────────────
        private string _lastGeoHash = "";
        private string _lastParamsHash = "";
        private string _lastResult = "";
        private string _lastStatus = "";
        private double _lastComputeTime = 0;

        // ─── Async state machine ─────────────────────────────────────────
        private enum RunState { Idle, HealthCheck, Sending, Polling, Done, Error }
        private volatile int _stateInt = 0; // int-backed for volatile safety
        private RunState _state
        {
            get => (RunState)_stateInt;
            set => _stateInt = (int)value;
        }
        private string _pendingResult = "";
        private string _pendingStatus = "";
        private double _pendingTime = 0;
        private string _pendingError = "";
        private string _pendingGeoHash = "";
        private string _pendingParamsHash = "";

        public SizerRun()
            : base("Sizer Run",
                   "SizerRun",
                   "Send geometry and parameters to the Julia sizing server",
                   "StructuralSizer", "Analysis")
        { }

        public override Guid ComponentGuid =>
            new Guid("A1B2C3D4-AAAA-BBBB-CCCC-DDDDEEEE0001");

        // ─── Parameters ──────────────────────────────────────────────────

        protected override void RegisterInputParams(GH_InputParamManager pManager)
        {
            pManager.AddGenericParameter("Geometry", "Geometry",
                "SizerGeometry from the GeometryInput component",
                GH_ParamAccess.item);

            pManager.AddGenericParameter("Params", "Params",
                "SizerParams from the DesignParams component",
                GH_ParamAccess.item);

            // Default Server URL: for AWS deployment, ask the user for the AWS server URL and set it here.
            pManager.AddTextParameter("Server URL", "URL",
                "Julia API server URL",
                GH_ParamAccess.item, "http://localhost:8080");

            pManager.AddBooleanParameter("Run", "Run",
                "Toggle to send the request (connect a Button)",
                GH_ParamAccess.item, false);
        }

        protected override void RegisterOutputParams(GH_OutputParamManager pManager)
        {
            pManager.AddTextParameter("JSON", "JSON",
                "Raw JSON response from the server", GH_ParamAccess.item);
            pManager.AddTextParameter("Status", "Status",
                "Response status (ok, error, cached)", GH_ParamAccess.item);
            pManager.AddNumberParameter("Compute Time", "Time",
                "Server compute time in seconds", GH_ParamAccess.item);
        }

        // ─── Right-click menu ────────────────────────────────────────────────

        protected override void AppendAdditionalComponentMenuItems(ToolStripDropDown menu)
        {
            base.AppendAdditionalComponentMenuItems(menu);
            Menu_AppendSeparator(menu);

            var resetItem = Menu_AppendItem(menu, "Reset Cache", OnResetCache);
            resetItem.ToolTipText = "Clear cached results and force a fresh analysis run";
        }

        private void OnResetCache(object sender, EventArgs e)
        {
            _lastGeoHash = "";
            _lastParamsHash = "";
            _lastResult = "";
            _lastStatus = "";
            _lastComputeTime = 0;
            Message = "Cache cleared";
            ExpireSolution(true);
        }

        // ─── Solve ───────────────────────────────────────────────────────

        protected override void SolveInstance(IGH_DataAccess DA)
        {
            // ── 1. Read inputs ──
            GH_SizerGeometry? geoGoo = null;
            GH_SizerParams? paramsGoo = null;
            string url = "http://localhost:8080";
            bool run = false;

            if (!DA.GetData(0, ref geoGoo) || geoGoo?.Value == null) return;
            if (!DA.GetData(1, ref paramsGoo) || paramsGoo?.Value == null) return;
            DA.GetData(2, ref url);
            DA.GetData(3, ref run);

            if (string.IsNullOrWhiteSpace(url))
                url = "http://localhost:8080";

            // ── 2. If async work just finished, harvest the result ──
            if (_state == RunState.Done)
            {
                _lastGeoHash = _pendingGeoHash;
                _lastParamsHash = _pendingParamsHash;
                _lastResult = _pendingResult;
                _lastStatus = _pendingStatus;
                _lastComputeTime = _pendingTime;
                _state = RunState.Idle;

                DA.SetData(0, _lastResult);
                DA.SetData(1, _lastStatus);
                DA.SetData(2, _lastComputeTime);

                if (_lastStatus == "error")
                    AddRuntimeMessage(GH_RuntimeMessageLevel.Error, ExtractErrorMessage(_lastResult));

                Message = _lastStatus == "error"
                    ? $"\u2717 Error"
                    : $"\u2713 {_lastComputeTime:F1} s";
                return;
            }

            if (_state == RunState.Error)
            {
                AddRuntimeMessage(GH_RuntimeMessageLevel.Error, _pendingError);
                Message = "\u2717 Server error";
                _state = RunState.Idle;

                DA.SetData(0, _lastResult);
                DA.SetData(1, "error");
                DA.SetData(2, 0.0);
                return;
            }

            // ── 3. If currently computing, show progress ──
            if (_state != RunState.Idle)
            {
                Message = _state == RunState.HealthCheck ? "Checking server..."
                        : _state == RunState.Sending     ? "Computing..."
                        : _state == RunState.Polling      ? "Queued..."
                        : "Working...";

                AddRuntimeMessage(GH_RuntimeMessageLevel.Remark, Message);

                // Output stale cached data while we wait
                if (!string.IsNullOrEmpty(_lastResult))
                {
                    DA.SetData(0, _lastResult);
                    DA.SetData(1, _lastStatus);
                    DA.SetData(2, _lastComputeTime);
                }
                return;
            }

            // ── 4. Run = false → show cached or "ready" ──
            if (!run)
            {
                if (!string.IsNullOrEmpty(_lastResult))
                {
                    DA.SetData(0, _lastResult);
                    DA.SetData(1, _lastStatus);
                    DA.SetData(2, _lastComputeTime);
                    Message = $"\u2713 {_lastComputeTime:F1} s (cached)";
                }
                else
                {
                    Message = "Ready";
                    AddRuntimeMessage(GH_RuntimeMessageLevel.Remark,
                        "Connect a Button to Run and click it to send the request.");
                }
                return;
            }

            // ── 5. Check for unchanged inputs ──
            var geo = geoGoo.Value;
            var prms = paramsGoo.Value;
            string geoHash = geo.ComputeHash();
            string paramsHash = prms.ComputeHash();

            if (geoHash == _lastGeoHash && paramsHash == _lastParamsHash
                && !string.IsNullOrEmpty(_lastResult))
            {
                DA.SetData(0, _lastResult);
                DA.SetData(1, "cached");
                DA.SetData(2, _lastComputeTime);
                Message = $"\u2713 {_lastComputeTime:F1} s (cached)";
                AddRuntimeMessage(GH_RuntimeMessageLevel.Remark,
                    "No changes detected \u2014 returning cached result.");
                return;
            }

            // ── 6. Build payload ──
            var payload = geo.ToJson();
            payload["params"] = prms.ToJson();

            if (geoHash == _lastGeoHash && paramsHash != _lastParamsHash)
                payload["geometry_hash"] = geoHash;

            string jsonBody = payload.ToString();

            // ── 7. Launch async: health check → POST /design → poll if queued ──
            _state = RunState.HealthCheck;
            _pendingGeoHash = geoHash;
            _pendingParamsHash = paramsHash;
            Message = "Checking server...";

            // Capture the document schedule callback for thread-safe expire
            var doc = OnPingDocument();

            Task.Run(async () =>
            {
                try
                {
                    // Health check
                    if (!await CheckHealth(url))
                    {
                        _pendingError = $"Julia server not running at {url}.\n" +
                            "Start it with:\n  julia --project=StructuralSynthesizer scripts/api/sizer_service.jl";
                        _state = RunState.Error;
                        ScheduleExpire(doc);
                        return;
                    }

                    // Send design request
                    _state = RunState.Sending;
                    ScheduleExpire(doc);

                    string responseJson = await PostDesign(url, jsonBody);

                    // Parse response
                    string status = "ok";
                    double computeTime = 0;

                    try
                    {
                        var jobj = JObject.Parse(responseJson);
                        status = jobj["status"]?.ToString() ?? "unknown";
                        computeTime = jobj["compute_time_s"]?.ToObject<double>() ?? 0;

                        if (status == "queued")
                        {
                            _state = RunState.Polling;
                            ScheduleExpire(doc);

                            responseJson = await PollUntilReady(url, 300);
                            var result = JObject.Parse(responseJson);
                            status = result["status"]?.ToString() ?? "unknown";
                            computeTime = result["compute_time_s"]?.ToObject<double>() ?? 0;
                        }
                    }
                    catch { /* parse errors are surfaced via status */ }

                    _pendingResult = responseJson;
                    _pendingStatus = status;
                    _pendingTime = computeTime;
                    _state = RunState.Done;
                }
                catch (TaskCanceledException)
                {
                    _pendingError = $"Request timed out after {_client.Timeout.TotalSeconds:F0}s. " +
                        "The server may still be computing — check its terminal.";
                    _state = RunState.Error;
                }
                catch (HttpRequestException ex)
                {
                    _pendingError = $"Connection failed: {ex.Message}\n" +
                        $"Is the Julia server running at {url}?\n" +
                        "Start it with:\n  julia --project=StructuralSynthesizer scripts/api/sizer_service.jl";
                    _state = RunState.Error;
                }
                catch (Exception ex)
                {
                    _pendingError = $"Unexpected error: {ex.Message}";
                    _state = RunState.Error;
                }

                ScheduleExpire(doc);
            });

            // Output stale data while the request is in flight
            if (!string.IsNullOrEmpty(_lastResult))
            {
                DA.SetData(0, _lastResult);
                DA.SetData(1, _lastStatus);
                DA.SetData(2, _lastComputeTime);
            }
        }

        // ─── Thread-safe solution expiry ─────────────────────────────────

        private void ScheduleExpire(GH_Document? doc)
        {
            if (doc == null) return;
            doc.ScheduleSolution(100, d =>
            {
                ExpireSolution(false);
            });
        }

        // ─── HTTP helpers ────────────────────────────────────────────────

        /// <summary>
        /// Quick health check — returns true if the server responds to GET /health
        /// within 3 seconds.
        /// </summary>
        private static async Task<bool> CheckHealth(string baseUrl)
        {
            try
            {
                using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(3));
                var resp = await _client.GetAsync(
                    $"{baseUrl.TrimEnd('/')}/health", cts.Token);
                return resp.IsSuccessStatusCode;
            }
            catch
            {
                return false;
            }
        }

        private static async Task<string> PostDesign(string baseUrl, string jsonBody)
        {
            var content = new StringContent(jsonBody, Encoding.UTF8, "application/json");
            var response = await _client.PostAsync($"{baseUrl.TrimEnd('/')}/design", content);
            return await response.Content.ReadAsStringAsync();
        }

        private static async Task<string> PollUntilReady(string baseUrl, int timeoutSeconds)
        {
            var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
            while (DateTime.UtcNow < deadline)
            {
                await Task.Delay(1000);
                try
                {
                    var resp = await _client.GetAsync($"{baseUrl.TrimEnd('/')}/status");
                    var body = await resp.Content.ReadAsStringAsync();
                    var jobj = JObject.Parse(body);
                    string st = jobj["status"]?.ToString() ?? "";
                    if (st == "idle")
                        return body;
                }
                catch { /* retry */ }
            }
            return "{\"status\":\"error\",\"message\":\"Timeout waiting for server\"}";
        }

        // ─── Helpers ─────────────────────────────────────────────────────

        private static string ExtractErrorMessage(string json)
        {
            try
            {
                var jobj = JObject.Parse(json);
                return jobj["message"]?.ToString() ?? "Unknown server error";
            }
            catch
            {
                return "Server returned an error.";
            }
        }
    }
}
