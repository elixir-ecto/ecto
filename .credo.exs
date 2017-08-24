%{configs: [
  %{name: "default",
    files: %{
      included: ["lib/", "test/", "integration_test/"],
      excluded: [~r"/_build/", ~r"/deps/"]
    },
    requires: [],
    check_for_updates: false,

    # You can customize the parameters of any check by adding a second element
    # to the tuple.
    #
    # To disable a check put `false` as second element:
    #
    #     {Credo.Check.Design.DuplicatedCode, false}
    #
    checks: [
      {Credo.Check.Consistency.ExceptionNames},
      {Credo.Check.Consistency.LineEndings},
      {Credo.Check.Consistency.MultiAliasImportRequireUse},
      {Credo.Check.Consistency.SpaceAroundOperators},
      {Credo.Check.Consistency.SpaceInParentheses},
      {Credo.Check.Consistency.TabsOrSpaces},

      {Credo.Check.Design.AliasUsage, false},
      {Credo.Check.Design.DuplicatedCode, excluded_macros: []},

      # Disabled for now as those are checked by Code Climate
      {Credo.Check.Design.TagTODO, false},
      {Credo.Check.Design.TagFIXME, false},

      {Credo.Check.Readability.FunctionNames},
      {Credo.Check.Readability.LargeNumbers, false}, # Because of Ecto migrations
      {Credo.Check.Readability.MaxLineLength, false},
      {Credo.Check.Readability.ModuleAttributeNames},
      {Credo.Check.Readability.ModuleDoc},
      {Credo.Check.Readability.ModuleNames},
      {Credo.Check.Readability.ParenthesesOnZeroArityDefs, false},
      {Credo.Check.Readability.ParenthesesInCondition},
      {Credo.Check.Readability.PredicateFunctionNames},
      {Credo.Check.Readability.SinglePipe, false}, # A common idiom in Ecto tests
      {Credo.Check.Readability.Specs, false},
      {Credo.Check.Readability.StringSigils},
      {Credo.Check.Readability.TrailingBlankLine},
      {Credo.Check.Readability.TrailingWhiteSpace},
      {Credo.Check.Readability.VariableNames},
      {Credo.Check.Readability.RedundantBlankLines},

      {Credo.Check.Refactor.ABCSize, false},
      {Credo.Check.Refactor.CondStatements},
      {Credo.Check.Refactor.DoubleBooleanNegation, false},
      {Credo.Check.Refactor.FunctionArity, max_arity: 13}, # Don't do this at home.
      {Credo.Check.Refactor.MatchInCondition},
      {Credo.Check.Refactor.PipeChainStart, false},
      {Credo.Check.Refactor.CyclomaticComplexity},
      {Credo.Check.Refactor.NegatedConditionsInUnless},
      {Credo.Check.Refactor.NegatedConditionsWithElse},
      {Credo.Check.Refactor.Nesting},
      {Credo.Check.Refactor.UnlessWithElse},
      {Credo.Check.Refactor.VariableRebinding, false},

      {Credo.Check.Warning.BoolOperationOnSameValues},
      {Credo.Check.Warning.IExPry},
      {Credo.Check.Warning.IoInspect, false},
      {Credo.Check.Warning.NameRedeclarationByAssignment, false},
      {Credo.Check.Warning.NameRedeclarationByCase, false},
      {Credo.Check.Warning.NameRedeclarationByDef, false},
      {Credo.Check.Warning.NameRedeclarationByFn, false},
      {Credo.Check.Warning.OperationOnSameValues, false}, # Disabled because of p.x == p.x in Ecto queries
      {Credo.Check.Warning.OperationWithConstantResult},
      {Credo.Check.Warning.UnusedEnumOperation},
      {Credo.Check.Warning.UnusedKeywordOperation},
      {Credo.Check.Warning.UnusedListOperation},
      {Credo.Check.Warning.UnusedStringOperation},
      {Credo.Check.Warning.UnusedTupleOperation},
    ]
  }
]}
