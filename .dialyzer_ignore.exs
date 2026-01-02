[
  # Legacy warnings from plug module
  ~r/Function put_feature\/2 has no local return/,
  ~r/Function put_feature\/3 has no local return/,

  # SimpleHttp behavior issues
  ~r/callback_info_missing/,
  ~r/@behaviour.*does not exist.*Unleash\.Http\.SimpleHttp\.Behavior/,

  # Dialyxir bugs - Protocol errors
  ~r/Protocol\.UndefinedError.*String\.Chars/,
  ~r/Unknown error occurred.*Protocol\.UndefinedError/,

  # Pattern matching warnings (false positives)
  ~r/pattern_match_cov/,
  ~r/The pattern.*can never match.*previous clauses completely cover/,
  ~r/The inferred return type.*has nothing in common.*expected return type/
]