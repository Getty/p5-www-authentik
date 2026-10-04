package WWW::Authentik::Error::Network;

# ABSTRACT: Raised when no HTTP answer came back from authentik

use Moo;
extends 'WWW::Authentik::Error';

our $VERSION = '0.001';

=description

The request never reached authentik, or no answer arrived: a refused
connection, a timeout, a name that does not resolve.

=cut

1;
