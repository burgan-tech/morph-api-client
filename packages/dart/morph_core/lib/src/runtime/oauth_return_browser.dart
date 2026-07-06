// dart:html is deprecated in favor of package:web; conditional web OAuth helper kept minimal.
// ignore_for_file: deprecated_member_use

import 'dart:html' as html;

import '../util/oauth_return.dart';

Uri? oauthReturnReadLocationUri() => Uri.tryParse(html.window.location.href);

void oauthReturnReplaceLocationHref(String href) {
  final stripped = stripOAuthReturnSearchParams(href);
  html.window.history.replaceState(null, '', stripped);
}
