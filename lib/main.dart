import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// WEBSITE
// ============================================================

const String websiteUrl = 'https://192.168.6.1/sheetal/sheetal/';

// ============================================================
// VERSION UPDATE SETTINGS
// ============================================================

const String versionJsonUrl = 'https://hashday.in/sheetal/version.json';

const String pmsTerminalUrl = 'https://pms.hashday.in/pms/terminal.php';

// ============================================================
// APP
// ============================================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('================================');
  debugPrint('WEBSITE URL = $websiteUrl');
  debugPrint('================================');

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const MyApp());
}

// ============================================================
// APP
// ============================================================

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dashboard',
      theme: ThemeData(useMaterial3: true),
      home: const DashboardWebView(),
    );
  }
}

// ============================================================
// DASHBOARD WEBVIEW
// ============================================================

class DashboardWebView extends StatefulWidget {
  const DashboardWebView({super.key});

  @override
  State<DashboardWebView> createState() => _DashboardWebViewState();
}

class _DashboardWebViewState extends State<DashboardWebView> {
  WebViewController? _controller;

  bool _loading = true;

  // ==========================================================
  // VERSION UPDATE
  // ==========================================================

  bool _checkingVersion = false;
  bool _updateStarted = false;

  // ==========================================================
  // TWO FINGER LONG SWIPE REFRESH
  // ==========================================================

  // Both fingers must move at least this distance.
  static const double refreshSwipeDistance = 300.0;

  // ==========================================================
  // TERMINAL DEVICE INFORMATION
  // ==========================================================

  String _deviceName = 'Unavailable';
  String _macAddress = 'Unavailable';
  String _deviceToken = 'Unavailable';
  String _imei1 = 'Unavailable';
  String _imei2 = 'Unavailable';
  String _appUptime = 'Unavailable';

  bool _terminalDetailsLoading = false;

  final Stopwatch _appUptimeWatch = Stopwatch();

  // ==========================================================
  // INITIALIZE
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _appUptimeWatch.start();

    _initializeWebView();

    _checkForUpdate();
  }

  // ============================================================
  // VERSION CHECK
  // ============================================================

  Future<void> _checkForUpdate() async {
    if (_checkingVersion || _updateStarted) {
      return;
    }

    _checkingVersion = true;

    try {
      debugPrint('================================');
      debugPrint('CHECKING APP VERSION');
      debugPrint('VERSION JSON: $versionJsonUrl');
      debugPrint('================================');

      final packageInfo = await PackageInfo.fromPlatform();

      final currentVersion = packageInfo.version;

      debugPrint('INSTALLED VERSION: $currentVersion');

      final response = await http
          .get(Uri.parse(versionJsonUrl))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint(
          'VERSION CHECK FAILED: '
          'HTTP ${response.statusCode}',
        );

        return;
      }

      final Map<String, dynamic> data = jsonDecode(response.body);

      final String serverVersion = (data['version'] ?? '').toString().trim();

      final String apkPath = (data['apkPath'] ?? '').toString().trim();

      debugPrint('SERVER VERSION: $serverVersion');

      debugPrint('APK PATH: $apkPath');

      if (serverVersion.isEmpty || apkPath.isEmpty) {
        debugPrint('VERSION JSON IS INVALID');

        return;
      }

      final comparison = _compareVersions(serverVersion, currentVersion);

      debugPrint(
        'VERSION COMPARISON RESULT: '
        '$comparison',
      );

      if (comparison > 0) {
        debugPrint('NEW VERSION AVAILABLE');

        await _downloadAndInstallUpdate(serverVersion, apkPath);
      } else {
        debugPrint('APP IS ALREADY UP TO DATE');
      }
    } catch (e, stackTrace) {
      debugPrint('VERSION CHECK ERROR: $e');

      debugPrint('$stackTrace');
    } finally {
      _checkingVersion = false;
    }
  }

  // ============================================================
  // VERSION COMPARISON
  // ============================================================

  int _compareVersions(String serverVersion, String currentVersion) {
    final serverParts = _parseVersion(serverVersion);

    final currentParts = _parseVersion(currentVersion);

    final maxLength = serverParts.length > currentParts.length
        ? serverParts.length
        : currentParts.length;

    for (int i = 0; i < maxLength; i++) {
      final serverNumber = i < serverParts.length ? serverParts[i] : 0;

      final currentNumber = i < currentParts.length ? currentParts[i] : 0;

      if (serverNumber > currentNumber) {
        return 1;
      }

      if (serverNumber < currentNumber) {
        return -1;
      }
    }

    return 0;
  }

  // ============================================================
  // PARSE VERSION
  // ============================================================

  List<int> _parseVersion(String version) {
    return version
        .split('.')
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .toList();
  }

  // ============================================================
  // DOWNLOAD + INSTALL APK
  // ============================================================

  Future<void> _downloadAndInstallUpdate(
    String serverVersion,
    String apkUrl,
  ) async {
    if (_updateStarted) {
      return;
    }

    _updateStarted = true;

    try {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'New version $serverVersion found. '
            'Updating...',
          ),
          duration: const Duration(seconds: 4),
        ),
      );

      debugPrint('================================');
      debugPrint('DOWNLOADING NEW APK');
      debugPrint('VERSION: $serverVersion');
      debugPrint('APK: $apkUrl');
      debugPrint('================================');

      final response = await http
          .get(Uri.parse(apkUrl))
          .timeout(const Duration(minutes: 5));

      if (response.statusCode != 200) {
        throw Exception(
          'APK download failed: '
          'HTTP ${response.statusCode}',
        );
      }

      if (response.bodyBytes.isEmpty) {
        throw Exception('Downloaded APK is empty');
      }

      final directory = await getTemporaryDirectory();

      final apkFile = File('${directory.path}/sheetal_update.apk');

      await apkFile.writeAsBytes(response.bodyBytes, flush: true);

      debugPrint('APK SAVED: ${apkFile.path}');

      final result = await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );

      debugPrint(
        'APK INSTALLER RESULT: '
        '${result.type}',
      );

      debugPrint(
        'APK INSTALLER MESSAGE: '
        '${result.message}',
      );
    } catch (e, stackTrace) {
      debugPrint('UPDATE ERROR: $e');

      debugPrint('$stackTrace');

      _updateStarted = false;

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('App update failed: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // ============================================================
  // TERMINAL.PHP DETECTION
  // ============================================================

  bool _isTerminalPage(String url) {
    try {
      final currentUri = Uri.tryParse(url);

      final pmsUri = Uri.tryParse(pmsTerminalUrl);

      debugPrint('========================================');

      debugPrint('PMS URL CHECK');
      debugPrint('Original URL: $url');
      debugPrint('Current URI: $currentUri');
      debugPrint('PMS Terminal URL: $pmsTerminalUrl');
      debugPrint('PMS URI: $pmsUri');

      if (currentUri == null || pmsUri == null) {
        return false;
      }

      final result =
          currentUri.scheme.toLowerCase() == pmsUri.scheme.toLowerCase() &&
          currentUri.host.toLowerCase() == pmsUri.host.toLowerCase() &&
          currentUri.path.toLowerCase() == pmsUri.path.toLowerCase();

      debugPrint('PMS TERMINAL CHECK: $result');

      return result;
    } catch (e) {
      debugPrint('PMS TERMINAL URL CHECK ERROR: $e');

      return false;
    }
  }

  // ============================================================
  // CREATE / RESTORE DEVICE TOKEN
  // ============================================================

  Future<void> _getDeviceToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      String? token = prefs.getString('sheetal_device_token');

      if (token == null || token.isEmpty) {
        final random = Random();

        token =
            '${DateTime.now().millisecondsSinceEpoch}-'
            '${List.generate(16, (_) => random.nextInt(10)).join()}';

        await prefs.setString('sheetal_device_token', token);

        debugPrint('NEW DEVICE TOKEN CREATED');

        debugPrint('DEVICE TOKEN: $token');
      } else {
        debugPrint('EXISTING DEVICE TOKEN FOUND');

        debugPrint('DEVICE TOKEN: $token');
      }

      _deviceToken = token;
    } catch (e) {
      debugPrint('DEVICE TOKEN ERROR: $e');

      _deviceToken = 'Unavailable';
    }
  }

  // ============================================================
  // LOAD TERMINAL DEVICE DETAILS
  // ============================================================

  Future<void> _loadTerminalDeviceDetails() async {
    if (_terminalDetailsLoading) {
      return;
    }

    if (_controller == null) {
      return;
    }

    _terminalDetailsLoading = true;

    try {
      debugPrint('================================');

      debugPrint('terminal.php DETECTED');

      debugPrint('FETCHING DEVICE DETAILS');

      debugPrint('================================');

      await _getDeviceToken();

      // ========================================================
      // DEVICE NAME
      // ========================================================

      try {
        final deviceInfo = DeviceInfoPlugin();

        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;

          final manufacturer = androidInfo.manufacturer.trim();

          final model = androidInfo.model.trim();

          if (manufacturer.isNotEmpty && model.isNotEmpty) {
            _deviceName = '$manufacturer $model';
          } else if (model.isNotEmpty) {
            _deviceName = model;
          }
        }
      } catch (e) {
        debugPrint('DEVICE NAME ERROR: $e');

        _deviceName = 'Unavailable';
      }

      // ========================================================
      // APP UPTIME
      // ========================================================

      final uptime = _appUptimeWatch.elapsed;

      final hours = uptime.inHours;

      final minutes = uptime.inMinutes.remainder(60);

      final seconds = uptime.inSeconds.remainder(60);

      if (hours > 0) {
        _appUptime =
            '${hours}h '
            '${minutes}m '
            '${seconds}s';
      } else if (minutes > 0) {
        _appUptime =
            '${minutes}m '
            '${seconds}s';
      } else {
        _appUptime = '${seconds}s';
      }

      // ========================================================
      // DEVICE TOKEN
      // ========================================================

      _macAddress = _deviceToken;

      _imei1 = 'Unavailable';

      _imei2 = 'Unavailable';

      debugPrint('--------------------------------');

      debugPrint('TERMINAL DEVICE DETAILS');

      debugPrint('Device Name : $_deviceName');

      debugPrint('Device Token: $_deviceToken');

      debugPrint('MAC Address : $_macAddress');

      debugPrint('IMEI 1      : $_imei1');

      debugPrint('IMEI 2      : $_imei2');

      debugPrint('App Uptime  : $_appUptime');

      debugPrint('--------------------------------');

      await _sendDeviceDetailsToTerminal();
    } catch (e, stackTrace) {
      debugPrint('TERMINAL DEVICE INFO ERROR: $e');

      debugPrint('$stackTrace');
    } finally {
      _terminalDetailsLoading = false;
    }
  }

  // ============================================================
  // SEND DEVICE DETAILS TO terminal.php
  // ============================================================

  Future<void> _sendDeviceDetailsToTerminal() async {
    if (_controller == null) {
      return;
    }

    final deviceName = jsonEncode(_deviceName);

    final macAddress = jsonEncode(_macAddress);

    final imei1 = jsonEncode(_imei1);

    final imei2 = jsonEncode(_imei2);

    final appUptime = jsonEncode(_appUptime);

    final javascript =
        '''
(function() {

  const deviceInfo = {
    deviceName: $deviceName,
    macAddress: $macAddress,
    imei1: $imei1,
    imei2: $imei2,
    appUptime: $appUptime
  };

  window.SheetalDeviceInfo =
      deviceInfo;

  console.log(
    "SHEETAL DEVICE INFO",
    deviceInfo
  );

  try {

    window.dispatchEvent(
      new CustomEvent(
        "sheetalDeviceInfoReady",
        {
          detail: deviceInfo
        }
      )
    );

  } catch (e) {

    console.log(
      "Custom event error:",
      e
    );
  }

  function setField(
    keywords,
    value
  ) {

    if (!value ||
        value === "Unavailable") {
      return false;
    }

    const elements =
      document.querySelectorAll(
        "input, textarea, select"
      );

    for (
      const element of elements
    ) {

      const text = (
        (element.id || "") +
        " " +
        (element.name || "") +
        " " +
        (element.placeholder || "") +
        " " +
        (
          element.getAttribute(
            "aria-label"
          ) || ""
        )
      ).toLowerCase();

      for (
        const keyword of keywords
      ) {

        if (
          text.includes(keyword)
        ) {

          try {

            if (
              element.tagName
                .toLowerCase() ===
              "select"
            ) {

              element.value =
                  value;

            } else {

              const prototype =
                  Object.getPrototypeOf(
                    element
                  );

              const valueSetter =
                  Object.getOwnPropertyDescriptor(
                    prototype,
                    "value"
                  );

              if (
                valueSetter &&
                valueSetter.set
              ) {

                valueSetter.set.call(
                  element,
                  value
                );

              } else {

                element.value =
                    value;
              }
            }

            element.dispatchEvent(
              new Event(
                "input",
                {
                  bubbles: true
                }
              )
            );

            element.dispatchEvent(
              new Event(
                "change",
                {
                  bubbles: true
                }
              )
            );

            console.log(
              "FIELD UPDATED:",
              keyword,
              value
            );

            return true;

          } catch (e) {

            console.log(
              "FIELD UPDATE ERROR:",
              e
            );
          }
        }
      }
    }

    return false;
  }

  setField(
    [
      "device_name",
      "devicename",
      "device name",
      "device"
    ],
    deviceInfo.deviceName
  );

  setField(
    [
      "device_token",
      "devicetoken",
      "device token",
      "mac_address",
      "macaddress",
      "mac address",
      "mac"
    ],
    deviceInfo.macAddress
  );

  setField(
    [
      "imei1",
      "imei_1",
      "imei 1",
      "imei-one",
      "imei one"
    ],
    deviceInfo.imei1
  );

  setField(
    [
      "imei2",
      "imei_2",
      "imei 2",
      "imei-two",
      "imei two"
    ],
    deviceInfo.imei2
  );

  setField(
    [
      "app_uptime",
      "appuptime",
      "app uptime",
      "uptime"
    ],
    deviceInfo.appUptime
  );

})();
''';

    try {
      await _controller!.runJavaScript(javascript);

      debugPrint('DEVICE DETAILS SENT TO terminal.php');
    } catch (e) {
      debugPrint('FAILED TO SEND DEVICE DETAILS: $e');
    }
  }

  // ============================================================
  // INITIALIZE WEBVIEW
  // ============================================================

  Future<void> _initializeWebView() async {
    try {
      // ========================================================
      // PERMISSIONS
      // ========================================================

      await Permission.camera.request();

      await Permission.microphone.request();

      // ========================================================
      // CREATE WEBVIEW
      // ========================================================

      final params = AndroidWebViewControllerCreationParams();

      final controller = WebViewController.fromPlatformCreationParams(params);

      // ========================================================
      // JAVASCRIPT
      // ========================================================

      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);

      // ========================================================
      // BACKGROUND
      // ========================================================

      await controller.setBackgroundColor(Colors.white);

      // ========================================================
      // TWO FINGER REFRESH CHANNEL
      // ========================================================

      await controller.addJavaScriptChannel(
        'LongSwipeRefresh',
        onMessageReceived: (JavaScriptMessage message) {
          debugPrint('================================');

          debugPrint('TWO FINGER LONG SWIPE DETECTED');

          debugPrint('MESSAGE: ${message.message}');

          debugPrint('================================');

          _refreshPage();
        },
      );

      // ========================================================
      // ANDROID SETTINGS
      // ========================================================

      if (controller.platform is AndroidWebViewController) {
        final androidController =
            controller.platform as AndroidWebViewController;

        // ------------------------------------------------------
        // FILE ACCESS
        // ------------------------------------------------------

        await androidController.setAllowFileAccess(true);

        await androidController.setAllowContentAccess(true);

        // ------------------------------------------------------
        // MEDIA
        // ------------------------------------------------------

        androidController.setMediaPlaybackRequiresUserGesture(false);

        // ------------------------------------------------------
        // CAMERA / MICROPHONE
        // ------------------------------------------------------

        await androidController.setOnPlatformPermissionRequest((request) async {
          debugPrint('WEBVIEW PERMISSION REQUEST');

          debugPrint('REQUESTED: ${request.types}');

          final cameraStatus = await Permission.camera.request();

          final microphoneStatus = await Permission.microphone.request();

          if (cameraStatus.isGranted && microphoneStatus.isGranted) {
            await request.grant();
          } else {
            await request.deny();
          }
        });

        // ------------------------------------------------------
        // FILE UPLOAD
        // ------------------------------------------------------

        await androidController.setOnShowFileSelector((
          FileSelectorParams params,
        ) async {
          try {
            final result = await FilePicker.platform.pickFiles(
              allowMultiple: params.mode == FileSelectorMode.openMultiple,
              type: FileType.any,
              withData: false,
            );

            if (result == null || result.files.isEmpty) {
              return <String>[];
            }

            final files = result.files
                .where((file) => file.path != null)
                .map((file) => Uri.file(file.path!).toString())
                .toList();

            return files;
          } catch (e) {
            debugPrint('FILE PICKER ERROR: $e');

            return <String>[];
          }
        });
      }

      // ========================================================
      // NAVIGATION DELEGATE
      // ========================================================

      await controller.setNavigationDelegate(
        NavigationDelegate(
          // ----------------------------------------------------
          // PAGE STARTED
          // ----------------------------------------------------
          onPageStarted: (String url) {
            debugPrint('================================');

            debugPrint('PAGE STARTED: $url');

            debugPrint('================================');

            if (!mounted) {
              return;
            }

            setState(() {
              _loading = true;
            });
          },

          // ----------------------------------------------------
          // PAGE FINISHED
          // ----------------------------------------------------
          onPageFinished: (String url) async {
            debugPrint('================================');

            debugPrint('PAGE FINISHED: $url');

            debugPrint('================================');

            if (!mounted) {
              return;
            }

            setState(() {
              _loading = false;
            });

            // -----------------------------------------------
            // TERMINAL PAGE
            // -----------------------------------------------

            if (_isTerminalPage(url)) {
              await _loadTerminalDeviceDetails();
            }

            // -----------------------------------------------
            // INSTALL TWO FINGER REFRESH
            // -----------------------------------------------

            await _installLongSwipeRefresh();
          },

          // ----------------------------------------------------
          // SSL
          // ----------------------------------------------------
          onSslAuthError: (SslAuthError error) async {
            debugPrint('================================');

            debugPrint('SSL CERTIFICATE ERROR');

            debugPrint('PROCEEDING WITH SSL');

            debugPrint('================================');

            await error.proceed();
          },

          // ----------------------------------------------------
          // NAVIGATION REQUEST
          // ----------------------------------------------------
          onNavigationRequest: (NavigationRequest request) {
            debugPrint('NAVIGATION: ${request.url}');

            return NavigationDecision.navigate;
          },

          // ----------------------------------------------------
          // WEB RESOURCE ERROR
          // ----------------------------------------------------
          onWebResourceError: (WebResourceError error) {
            debugPrint('================================');

            debugPrint('WEBVIEW ERROR');

            debugPrint('URL: ${error.url}');

            debugPrint(
              'DESCRIPTION: '
              '${error.description}',
            );

            debugPrint('CODE: ${error.errorCode}');

            debugPrint(
              'MAIN FRAME: '
              '${error.isForMainFrame}',
            );

            debugPrint('================================');
          },
        ),
      );

      // ========================================================
      // SET CONTROLLER
      // ========================================================

      if (!mounted) {
        return;
      }

      setState(() {
        _controller = controller;
        _loading = true;
      });

      // ========================================================
      // LOAD WEBSITE
      // ========================================================

      debugPrint('================================');

      debugPrint('OPENING WEBSITE:');

      debugPrint(websiteUrl);

      debugPrint('================================');

      await controller.loadRequest(Uri.parse(websiteUrl));
    } catch (e, stackTrace) {
      debugPrint('WEBVIEW INITIALIZATION ERROR: $e');

      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });
    }
  }

  // ============================================================
  // TWO FINGER LONG SWIPE REFRESH
  // ============================================================
  //
  // ONE FINGER:
  //     Normal scrolling.
  //
  // TWO FINGERS:
  //     Start at top.
  //     Both fingers move downward.
  //     Both must move 300 pixels.
  //     Then refresh.
  //
  // ============================================================

  Future<void> _installLongSwipeRefresh() async {
    if (_controller == null) {
      return;
    }

    final javascript =
        '''
(function() {

  // ========================================================
  // PREVENT DUPLICATE INSTALLATION
  // ========================================================

  if (window.__sheetalTwoFingerRefresh) {

    console.log(
      "TWO FINGER REFRESH ALREADY INSTALLED"
    );

    return;
  }

  window.__sheetalTwoFingerRefresh = true;

  // ========================================================
  // SETTINGS
  // ========================================================

  const REQUIRED_DISTANCE =
      $refreshSwipeDistance;

  // ========================================================
  // STATE
  // ========================================================

  let tracking = false;
  let triggered = false;

  let startY1 = 0;
  let startY2 = 0;

  // ========================================================
  // GET PAGE SCROLL
  // ========================================================

  function getScrollTop() {

    return (
      window.pageYOffset ||
      document.documentElement.scrollTop ||
      document.body.scrollTop ||
      0
    );

  }

  // ========================================================
  // TOUCH START
  // ========================================================

  document.addEventListener(
    'touchstart',
    function(event) {

      // -----------------------------------------------
      // MUST HAVE EXACTLY TWO FINGERS
      // -----------------------------------------------

      if (!event.touches ||
          event.touches.length !== 2) {

        tracking = false;
        triggered = false;

        return;
      }

      // -----------------------------------------------
      // MUST START AT PAGE TOP
      // -----------------------------------------------

      const scrollTop =
          getScrollTop();

      if (scrollTop > 2) {

        console.log(
          "TWO FINGER REFRESH:"
          + " PAGE NOT AT TOP"
        );

        tracking = false;

        return;
      }

      // -----------------------------------------------
      // SAVE BOTH START POSITIONS
      // -----------------------------------------------

      startY1 =
          event.touches[0].clientY;

      startY2 =
          event.touches[1].clientY;

      tracking = true;
      triggered = false;

      console.log(
        "TWO FINGER TRACKING STARTED"
      );

    },
    {
      passive: true
    }
  );

  // ========================================================
  // TOUCH MOVE
  // ========================================================

  document.addEventListener(
    'touchmove',
    function(event) {

      if (!tracking ||
          triggered ||
          !event.touches ||
          event.touches.length !== 2) {

        return;
      }

      // -----------------------------------------------
      // CURRENT POSITIONS
      // -----------------------------------------------

      const currentY1 =
          event.touches[0].clientY;

      const currentY2 =
          event.touches[1].clientY;

      // -----------------------------------------------
      // DISTANCE OF EACH FINGER
      // -----------------------------------------------

      const distance1 =
          currentY1 - startY1;

      const distance2 =
          currentY2 - startY2;

      // -----------------------------------------------
      // BOTH MUST MOVE DOWN
      // -----------------------------------------------

      if (distance1 <= 0 ||
          distance2 <= 0) {

        return;
      }

      // -----------------------------------------------
      // BOTH MUST REACH 300 PIXELS
      // -----------------------------------------------

      if (
          distance1 >= REQUIRED_DISTANCE &&
          distance2 >= REQUIRED_DISTANCE
      ) {

        triggered = true;
        tracking = false;

        console.log(
          "================================"
        );

        console.log(
          "TWO FINGER LONG SWIPE"
        );

        console.log(
          "REFRESH TRIGGERED"
        );

        console.log(
          "Finger 1:",
          distance1
        );

        console.log(
          "Finger 2:",
          distance2
        );

        console.log(
          "================================"
        );

        // ---------------------------------------------
        // SEND MESSAGE TO FLUTTER
        // ---------------------------------------------

        if (
            window.LongSwipeRefresh
        ) {

          window.LongSwipeRefresh.postMessage(
            "two_finger_refresh"
          );

        }

      }

    },
    {
      passive: true
    }
  );

  // ========================================================
  // TOUCH END
  // ========================================================

  document.addEventListener(
    'touchend',
    function(event) {

      if (
          !event.touches ||
          event.touches.length === 0
      ) {

        tracking = false;

        startY1 = 0;
        startY2 = 0;

      }

    },
    {
      passive: true
    }
  );

  // ========================================================
  // TOUCH CANCEL
  // ========================================================

  document.addEventListener(
    'touchcancel',
    function() {

      tracking = false;
      triggered = false;

      startY1 = 0;
      startY2 = 0;

    },
    {
      passive: true
    }
  );

  // ========================================================
  // DEBUG
  // ========================================================

  console.log(
    "================================"
  );

  console.log(
    "SHEETAL TWO FINGER REFRESH"
  );

  console.log(
    "INSTALLED"
  );

  console.log(
    "Required distance:",
    REQUIRED_DISTANCE
  );

  console.log(
    "One finger refresh: DISABLED"
  );

  console.log(
    "Two finger refresh: ENABLED"
  );

  console.log(
    "================================"
  );

})();
''';

    try {
      await _controller!.runJavaScript(javascript);

      debugPrint('================================');

      debugPrint('TWO FINGER REFRESH INSTALLED');

      debugPrint('ONE FINGER: NO REFRESH');

      debugPrint('TWO FINGER: REFRESH ENABLED');

      debugPrint(
        'THRESHOLD: '
        '$refreshSwipeDistance pixels',
      );

      debugPrint('================================');
    } catch (e) {
      debugPrint(
        'TWO FINGER REFRESH INSTALL ERROR: '
        '$e',
      );
    }
  }

  // ============================================================
  // REFRESH PAGE
  // ============================================================

  Future<void> _refreshPage() async {
    if (_controller == null) {
      return;
    }

    if (_loading) {
      debugPrint('REFRESH IGNORED - PAGE LOADING');

      return;
    }

    debugPrint('================================');

    debugPrint('TWO FINGER REFRESH');

    debugPrint('RELOADING WEBVIEW');

    debugPrint('================================');

    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      await _controller!.reload();
    } catch (e) {
      debugPrint('REFRESH ERROR: $e');

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ============================================================
  // ANDROID BACK BUTTON
  // ============================================================

  Future<bool> _handleBack() async {
    if (_controller == null) {
      return true;
    }

    if (await _controller!.canGoBack()) {
      await _controller!.goBack();

      return false;
    }

    return true;
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,

      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) {
          return;
        }

        final shouldExit = await _handleBack();

        if (shouldExit && mounted) {
          Navigator.of(context).pop();
        }
      },

      child: Scaffold(
        backgroundColor: Colors.white,

        body: Stack(
          children: [
            // ==================================================
            // WEBVIEW
            // ==================================================
            if (_controller != null)
              Positioned.fill(child: WebViewWidget(controller: _controller!)),

            // ==================================================
            // INITIAL LOADING
            // ==================================================
            if (_controller == null)
              const Center(child: CircularProgressIndicator()),

            // ==================================================
            // LOADING BAR
            // ==================================================
            if (_controller != null && _loading)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}
