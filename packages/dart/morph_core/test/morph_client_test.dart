import 'package:morph_core/morph_core.dart';
import 'package:test/test.dart';

void main() {
  test('MorphClient.init is unimplemented scaffold', () {
    expect(
      () => MorphClient.init({}, {}),
      throwsA(isA<UnimplementedError>()),
    );
  });
}
