# Unreleased

These changes are available in the current source build. The published v0.1.0 packages are unchanged.

- Added optional automatic renewal of the saved Canvas personal access token, enabled by default. While Syllapace is running, it checks expiry and extends the existing token near its expiry date when permitted by Canvas. Settings displays the expiry or a recovery message. Expired or rejected tokens require manual replacement.
- Fixed the empty states in Today, Timeline, Review, and search results so they center within the full remaining content area.
- Added Chinese and English renewal messages and automated coverage for renewal boundaries, failures, cancellation, and empty-state layout.
