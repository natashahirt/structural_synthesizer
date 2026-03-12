# =============================================================================
# Launch a Cursor Cloud Agent that posts a test message to Slack.
#
# Prerequisites:
#   1. CURSOR_API_KEY set in your environment (same key as in GitHub secrets).
#   2. SLACK_WEBHOOK_URL configured in Cursor Dashboard for the agent's
#      workspace (Settings → Environment / Secrets) so the agent can see it.
#
# Usage:
#   set CURSOR_API_KEY=your_key
#   julia scripts/runners/launch_slack_test_agent.jl
#
# The agent is given a single task: run curl to POST to SLACK_WEBHOOK_URL.
# =============================================================================

using Pkg
Pkg.activate(joinpath(@__DIR__, "..", "..", "StructuralSynthesizer"))
using Dates
using HTTP
using JSON
using Base64

const api_key = get(ENV, "CURSOR_API_KEY", "")
if isempty(api_key)
    error("CURSOR_API_KEY is not set. Set it in your environment and run again.")
end

prompt = """
Your only task: send one short message to Slack.

1. The webhook URL is in the environment variable SLACK_WEBHOOK_URL in this environment.
2. Use curl to POST a JSON payload to that URL. The body must be JSON with a "text" field. Example (run this, substituting the value of SLACK_WEBHOOK_URL):
   curl -s -X POST -H "Content-Type: application/json" -d '{"text":"Test from Cursor agent"}' "\$SLACK_WEBHOOK_URL"
3. Run the curl command. Confirm in your response that you did it, or report any error (e.g. if SLACK_WEBHOOK_URL is not set).
"""

repo = "https://github.com/natashahirt/menegroth"
branch = "cursor/slack-test"

body = Dict(
    "prompt" => Dict("text" => prompt),
    "model" => "gpt-5.2",
    "source" => Dict("repository" => repo, "ref" => "main"),
    "target" => Dict("autoCreatePr" => false, "branchName" => branch),
)

auth = base64encode(api_key * ":")

println("Launching Cursor agent (repo=$repo, branch=$branch)...")
resp = HTTP.post(
    "https://api.cursor.com/v0/agents";
    headers = ["Content-Type" => "application/json", "Authorization" => "Basic $auth"],
    body = JSON.json(body),
)

println("Status: ", resp.status)
println(String(resp.body))

if resp.status != 200
    exit(1)
end

# Parse and show agent id if present
try
    r = JSON.parse(String(resp.body))
    if haskey(r, "id")
        println("Agent id: ", r["id"])
    end
    if haskey(r, "error")
        println("Error: ", r["error"])
        exit(1)
    end
catch
end
