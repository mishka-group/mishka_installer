# Event/installer flows broadcast over PubSub after async compile/queue work, so every
# `assert_receive` waits up to 3s (the default is 100ms) to keep the suite deterministic under load.
# Tests do not pass their own timeout.
#
# `:distributed` tests spin up real peer nodes (EPMD + distribution) and are excluded by default;
# run them with `mix test --only distributed`. `:production_release` builds a real `mix release` and
# cold-restarts it (slow) — run with `mix test --only production_release`.
ExUnit.start(assert_receive_timeout: 3_000, exclude: [:distributed, :production_release])
