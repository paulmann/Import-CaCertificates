@{
    # Repository-wide PSScriptAnalyzer configuration.
    # Fail the build on Error and Warning; rules that do not apply to this project
    # are excluded below with a reason.
    Severity           = @('Error', 'Warning')
    IncludeDefaultRules = $true
    ExcludeRules       = @(
        # Test helpers create throw-away certificates by design and are not part of
        # the shipped module; the rule cannot be satisfied meaningfully there.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
