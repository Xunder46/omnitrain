/// What the phone can tell about its watch: the pairing right now, every change,
/// and every frame it heard. Implemented by the watch transport; the status
/// state depends on this and nothing platform-specific (plan 47c).
library;

import 'watch_link_info.dart';

abstract interface class WatchLinkSource {
  Future<WatchLinkInfo> linkInfo();
  Stream<WatchLinkInfo> get linkChanges;
  Stream<DateTime> get heard;
}
