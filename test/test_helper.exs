# Event/installer flows broadcast over PubSub after async compile/queue work, so give
# `assert_receive` headroom beyond the 100ms default to keep the suite deterministic under load.
#
# `:distributed` tests spin up real peer nodes (EPMD + distribution) and are excluded by default;
# run them with `mix test --only distributed`. `:production_release` builds a real `mix release` and
# cold-restarts it (slow) — run with `mix test --only production_release`.
ExUnit.start(assert_receive_timeout: 1_000, exclude: [:distributed, :production_release])
