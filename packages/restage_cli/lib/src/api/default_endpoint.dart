/// The backend a new sign-in uses when no endpoint is given: Restage Cloud.
/// A build can replace it with `--define=RESTAGE_DEFAULT_ENDPOINT=<url>`.
const defaultRestageEndpoint = String.fromEnvironment(
  'RESTAGE_DEFAULT_ENDPOINT',
  defaultValue: 'https://api.restage.dev/',
);
