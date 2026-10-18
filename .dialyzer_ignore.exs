[
  # OTP specs `:mnesia.error_description/1` as returning a string, so dialyzer concludes the
  # `is_tuple/1` guard of Error.describe/1 can never succeed. The function returns a tuple such as
  # `{~c"Bad type on some provided arguments", :foo}`, and the first clause of describe/1 runs.
  {"lib/helper/mnesia_assistant/error.ex", :guard_fail}
]
