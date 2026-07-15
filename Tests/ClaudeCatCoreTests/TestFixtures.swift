// Inline jsonl fixtures mimicking real Claude Code transcript lines.
// Kept as string constants on purpose: no resource bundles, works on Linux.
enum TestFixtures {
    // Assistant line with all four usage fields and a fractional-seconds timestamp.
    static let assistantFullUsage = """
    {"parentUuid":"aaaa-1","isSidechain":false,"userType":"external","cwd":"/Users/example/projects/demo","sessionId":"sess-1","version":"2.0.0","gitBranch":"main","type":"assistant","uuid":"uuid-1","timestamp":"2026-07-10T19:16:50.064Z","requestId":"req_1","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-fable-5","content":[{"type":"text","text":"Hello"}],"stop_reason":null,"usage":{"input_tokens":12,"cache_creation_input_tokens":345,"cache_read_input_tokens":6789,"output_tokens":42,"service_tier":"standard","server_tool_use":{"web_search_requests":0},"cache_creation":{"ephemeral_5m_input_tokens":345,"ephemeral_1h_input_tokens":0}}}}
    """

    // Same shape but the timestamp has no fractional seconds.
    static let assistantNonFractionalTimestamp = """
    {"type":"assistant","uuid":"uuid-2","timestamp":"2026-07-10T19:31:00Z","requestId":"req_2","message":{"id":"msg_2","type":"message","role":"assistant","model":"claude-fable-5","content":[],"usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":4}}}
    """

    // User line — must be skipped by the prefilter (no "usage" substring at all
    // would also skip it, but this one deliberately mentions usage in the text).
    static let userMessage = """
    {"parentUuid":null,"isSidechain":false,"userType":"external","cwd":"/Users/example/projects/demo","sessionId":"sess-1","type":"user","uuid":"uuid-3","timestamp":"2026-07-10T19:16:40.000Z","message":{"role":"user","content":"please check token usage for the assistant"}}
    """

    // Tool-result line: type "user" carrying a tool_result block.
    static let toolResult = """
    {"parentUuid":"uuid-1","type":"user","uuid":"uuid-4","timestamp":"2026-07-10T19:16:55.000Z","message":{"role":"user","content":[{"tool_use_id":"toolu_1","type":"tool_result","content":"ok"}]},"toolUseResult":{"stdout":"ok"}}
    """

    // Assistant line whose message has no usage object at all.
    static let assistantWithoutUsage = """
    {"type":"assistant","uuid":"uuid-5","timestamp":"2026-07-10T19:17:00.000Z","requestId":"req_5","message":{"id":"msg_5","type":"message","role":"assistant","model":"claude-fable-5","content":[{"type":"text","text":"usage-less"}]}}
    """

    // Assistant line without a top-level requestId.
    static let assistantMissingRequestId = """
    {"type":"assistant","uuid":"uuid-6","timestamp":"2026-07-10T19:18:00.000Z","message":{"id":"msg_6","type":"message","role":"assistant","model":"claude-fable-5","content":[],"usage":{"input_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":7}}}
    """

    // Assistant line without message.id and without requestId.
    static let assistantMissingBothIds = """
    {"type":"assistant","uuid":"uuid-7","timestamp":"2026-07-10T19:19:00.000Z","message":{"type":"message","role":"assistant","model":"claude-fable-5","content":[],"usage":{"input_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":7}}}
    """

    // Assistant line whose usage object lacks cache_read_input_tokens.
    static let assistantMissingCacheRead = """
    {"type":"assistant","uuid":"uuid-8","timestamp":"2026-07-10T19:20:00.000Z","requestId":"req_8","message":{"id":"msg_8","type":"message","role":"assistant","model":"claude-fable-5","content":[],"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"output_tokens":30}}}
    """

    // Broken JSON that still contains both prefilter substrings.
    static let brokenJson = """
    { not json "assistant" "usage"
    """

    // Assistant line with usage but a timestamp no formatter can parse.
    static let assistantBadTimestamp = """
    {"type":"assistant","uuid":"uuid-9","timestamp":"yesterday","requestId":"req_9","message":{"id":"msg_9","type":"message","role":"assistant","model":"claude-fable-5","content":[],"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}
    """
}
