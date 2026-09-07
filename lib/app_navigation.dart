import 'package:flutter/foundation.dart';

/// The selected bottom-nav tab index, hoisted to a global so non-widget code
/// (e.g. the announcements Realtime handler tapping the in-app banner) can
/// switch tabs. [RootNav] both drives and reflects this.
final ValueNotifier<int> rootTab = ValueNotifier<int>(0);

// Tab indices in [RootNav], in bottom-bar order. Kept here (not as bare
// literals) so dashboard shortcuts and the banner tap stay correct if the bar
// is ever reordered.
const int kHomeTabIndex = 0;
const int kScheduleTabIndex = 1;
const int kDiscoverTabIndex = 2;
const int kNewsTabIndex = 3;
const int kResourcesTabIndex = 4;
