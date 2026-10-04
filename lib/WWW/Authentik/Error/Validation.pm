package WWW::Authentik::Error::Validation;

# ABSTRACT: Raised for wrong arguments, missing credentials and rejected tokens

use Moo;
extends 'WWW::Authentik::Error';

our $VERSION = '0.002';

=description

Nothing was sent to authentik: the arguments did not make sense, a required
credential was missing, or a token did not pass L<WWW::Authentik::OIDC/verify_token>.

=cut

1;
