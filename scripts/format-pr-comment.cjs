"use strict";

// Preserve PR #48's byte-bound/artifact-first design. Metadata mode never
// consumes assistant prose, even if a caller accidentally supplies it here.
const MAX_COMMENT_BYTES = 60000;

function truncateUtf8(value, maxBytes) {
  const bytes = Buffer.from(String(value), "utf8");
  if (bytes.length <= maxBytes) return String(value);
  let end = Math.max(0, maxBytes);
  while (end > 0 && (bytes[end] & 0xc0) === 0x80) end--;
  return bytes.subarray(0, end).toString("utf8");
}

function plain(value, limit) {
  return truncateUtf8(String(value ?? "").replace(/[\r\n\x00-\x1f]/g, " "), limit)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/[\\`*_{}[\]()!#|]/g, "\\$&");
}

function workflowUrl(value) {
  const text = String(value ?? "");
  return /^https:\/\/[a-zA-Z0-9.-]+\/[a-zA-Z0-9_.-]+\/[a-zA-Z0-9_.-]+\/actions\/runs\/[0-9]+(?:\/artifacts\/[0-9]+)?$/.test(text)
    ? text : "";
}

function formatPrComment(options) {
  const visibility = options.visibility ?? "metadata-only";
  if (!["metadata-only", "full"].includes(visibility)) throw new Error("publication_policy_invalid");
  const rawTitle = truncateUtf8(String(options.title ?? "Automated Standards Validation").replace(/[\r\n]/g, " "), 200);
  const markerId = rawTitle.toLowerCase().replace(/[^a-z0-9]+/g, "-");
  const marker = `<!-- usable-pr-validator:${markerId} -->`;
  const status = options.validationOutcome === "success"
    && ["passed", "failed"].includes(options.validationStatus)
    ? options.validationStatus : "error";
  const rawCritical = String(options.criticalIssues ?? "");
  const critical = /^(0|[1-9][0-9]{0,3})$/.test(rawCritical) && Number(rawCritical) <= 1000
    ? rawCritical : "unavailable";
  const grounding = ["complete", "incomplete", "not-required"].includes(options.groundingStatus)
    ? options.groundingStatus : "unavailable";
  const runUrl = workflowUrl(options.runUrl);
  const candidateArtifactUrl = workflowUrl(options.artifactUrl);
  const artifactUrl = candidateArtifactUrl && runUrl && candidateArtifactUrl.startsWith(`${runUrl}/artifacts/`)
    ? candidateArtifactUrl : "";
  const artifact = artifactUrl
    ? `[Published report artifact](${artifactUrl}).`
    : runUrl ? `Report artifact link unavailable; inspect the [workflow run](${runUrl}).`
      : "Report artifact link unavailable.";
  const prefix = `${marker}\n## 🤖 ${plain(rawTitle, 200)}\n\n`
    + `**Action result: ${status.toUpperCase()}** · Critical issues: ${critical} · Grounding: ${grounding}\n\n`
    + `${artifact}\n\n`;
  if (visibility === "metadata-only") {
    return { marker, body: prefix + "Only action-generated metadata is published. Assistant prose, source excerpts, and retrieved standards are withheld.", truncated: false };
  }
  const report = String(options.report ?? "");
  const notice = "\n\n**Report excerpt truncated for GitHub's comment limit. The action result above is unchanged; consult the published report artifact.**";
  const budget = MAX_COMMENT_BYTES - Buffer.byteLength(prefix, "utf8");
  if (Buffer.byteLength(report, "utf8") <= budget)
    return { marker, body: prefix + report, truncated: false };
  return { marker, body: prefix + truncateUtf8(report, budget - Buffer.byteLength(notice, "utf8")) + notice, truncated: true };
}

module.exports = { formatPrComment, MAX_COMMENT_BYTES };
