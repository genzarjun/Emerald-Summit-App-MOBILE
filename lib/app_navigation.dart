import 'package:flutter/foundation.dart';

/// The selected bottom-nav tab index, hoisted to a global so non-widget code
/// (e.g. the announcements Realtime handler tapping the in-app banner) can
/// switch tabs. [RootNav] both drives and reflects this.
final ValueNotifier<int> rootTab = ValueNotifier<int>(0);

/// Index of the News (announcements) tab in [RootNav].
const int kNewsTabIndex = 2;
