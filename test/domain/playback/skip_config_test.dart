import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/playback/skip_config.dart';

void main() {
  test('默认 0/0', () {
    const c = SkipConfig();
    expect(c.introSeconds, 0);
    expect(c.outroSeconds, 0);
  });
  test('copyWith 只改指定字段', () {
    const c = SkipConfig(introSeconds: 90, outroSeconds: 60);
    expect(c.copyWith(introSeconds: 30), const SkipConfig(introSeconds: 30, outroSeconds: 60));
  });
  test('toJson/fromJson 往返', () {
    const c = SkipConfig(introSeconds: 90, outroSeconds: 60);
    expect(SkipConfig.fromJson(c.toJson()), c);
  });
  test('fromJson 缺字段回退 0', () {
    expect(SkipConfig.fromJson(const {}), const SkipConfig());
  });
}
