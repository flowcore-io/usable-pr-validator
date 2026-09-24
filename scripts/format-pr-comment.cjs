"use strict";

// Bound presentation only. Validation and the complete report artifact are
// owned by validate.sh; truncating a comment never changes their verdict.
const MAX_COMMENT_BYTES = 60000;

function truncateUtf8(value, maxBytes) {
  const bytes = Buffer.from(String(value), "utf8");
  if (bytes.length <= maxBytes) return String(value);
  let end = Math.max(0, maxBytes);
  while (end > 0 && (bytes[end] & 0xc0) === 0x80) end--;
  return bytes.subarray(0, end).toString("utf8");
}

function singleLine(value, limit) {
  return truncateUtf8(String(value ?? "").replace(/[\r\n]/g, " "), limit);
}

function formatPrComment(options) {
  const title = singleLine(options.title, 200);
  const markerId = title.toLowerCase().replace(/[^a-z0-9]+/g, "-");
  const marker = `<!-- usable-pr-validator:${markerId} -->`;
  const status = options.validationOutcome === "success"
    && ["passed", "failed"].includes(options.validationStatus)
    ? options.validationStatus : "error";
  const critical = /^\d{1,9}$/.test(String(options.criticalIssues))
    ? String(options.criticalIssues) : "unavailable";
  const grounding = ["complete", "incomplete", "not-required"].includes(options.groundingStatus)
    ? options.groundingStatus : "unavailable";
  const runUrl = singleLine(options.runUrl, 1000);
  const artifactUrl = singleLine(options.artifactUrl, 1000);
  const artifactName = singleLine(options.artifactName, 200);
  const artifact = artifactUrl
    ? `[Full validated report artifact](${artifactUrl}) (\`${artifactName}\`).`
    : `Report artifact link unavailable; inspect the [workflow run](${runUrl}).`;
  const prefix = `${marker}\n## 🤖 ${title}\n\n`
    + `**Action result: ${status.toUpperCase()}** · Critical issues: ${critical} · Grounding: ${grounding}\n\n`
    + `${artifact}\n\n`;
  const suffix = "\n\n---\n<details>\n<summary>📊 Validation Statistics</summary>\n\n"
    + `- **Model**: ${singleLine(options.modelInfo, 200)}\n`
    + `- **Standards Source**: ${singleLine(options.standardsSource, 500)}\n`
    + `- **Commit**: ${singleLine(options.commit, 40)}\n`
    + `- **Triggered by**: @${singleLine(options.actor, 100)}\n\n</details>`;
  const report = String(options.report);
  const budget = MAX_COMMENT_BYTES - Buffer.byteLength(prefix + suffix, "utf8");
  if (Buffer.byteLength(report, "utf8") <= budget)
    return { marker, body: prefix + report + suffix, truncated: false };

  const notice = "\n\n**Report excerpt truncated for GitHub's comment limit. The action result above is unchanged; consult the full report artifact for all findings.**";
  const excerpt = truncateUtf8(report, budget - Buffer.byteLength(notice, "utf8"));
  return { marker, body: prefix + excerpt + notice + suffix, truncated: true };
}

module.exports = { formatPrComment, MAX_COMMENT_BYTES };
