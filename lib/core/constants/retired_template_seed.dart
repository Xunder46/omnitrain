/// Ids of the template rows the first-install seed used to write for four templates
/// nothing creates. `RetiredTemplateRowsCleanup` removes exactly these, once, from phones
/// that already hold them. Keep these maps frozen: they name rows that must never be
/// matched by anything a user can create.
library;

class RetiredTemplateSeed {
  RetiredTemplateSeed._();

  /// Retired segment id -> the retired template it hung under.
  static const Map<String, String> segmentTemplate = {
    'tseg-upper-1': 'template-upper-strength',
    'tseg-run-1': 'template-easy-run',
    'tseg-boxing-1': 'template-boxing-rounds',
    'tseg-mobility-1': 'template-mobility',
  };

  /// Retired effort id -> the retired segment it hung under.
  static const Map<String, String> effortSegment = {
    'teff-upper-bench': 'tseg-upper-1',
    'teff-upper-ohp': 'tseg-upper-1',
    'teff-upper-row': 'tseg-upper-1',
    'teff-run-main': 'tseg-run-1',
    'teff-boxing-bag': 'tseg-boxing-1',
    'teff-mobility-stretch': 'tseg-mobility-1',
  };

  /// Retired target id -> the retired effort it hung under.
  static const Map<String, String> targetEffort = {
    'ttar-bench-sets': 'teff-upper-bench',
    'ttar-run-duration': 'teff-run-main',
    'ttar-boxing-rounds': 'teff-boxing-bag',
    'ttar-boxing-duration': 'teff-boxing-bag',
    'ttar-stretch-duration': 'teff-mobility-stretch',
  };

  /// The four retired template ids.
  static const List<String> templateIds = [
    'template-upper-strength',
    'template-easy-run',
    'template-boxing-rounds',
    'template-mobility',
  ];
}
