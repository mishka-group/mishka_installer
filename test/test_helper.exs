# Event/installer flows broadcast over PubSub after async compile/queue work, so give
# `assert_receive` headroom beyond the 100ms default to keep the suite deterministic under load.
ExUnit.start(assert_receive_timeout: 1_000)
