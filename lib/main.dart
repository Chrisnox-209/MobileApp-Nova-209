import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'rtsp_camera_widget.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:ui';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  WakelockPlus.enable();
  
  runApp(const OnboardRelayApp());
}

class OnboardRelayApp extends StatefulWidget {
  const OnboardRelayApp({super.key});

  @override
  State<OnboardRelayApp> createState() => _OnboardRelayAppState();
}

class _OnboardRelayAppState extends State<OnboardRelayApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  int _currentIndex = 0;
  bool _ecoModeEnabled = false;
  int _ecoCountdown = 0;
  Timer? _ecoTimer;
  int _tapCount = 0;
  DateTime? _lastTapTime;
  String _selectedCodec = "H.265";
  String _selectedProtocol = "RTSP";
  double _videoBitrate = 2.0;
  String _selectedResolution = "720p";
  int _selectedFps = 24;
  String _selectedBitrateMode = "CBR";
  String _serverToken = "";
  String _serverIp = "192.168.1.100";
  String _serverPort = "14550";
  bool _showPreview = false;

  final Battery _battery = Battery();
  int _phoneBatteryLevel = 0;
  late StreamSubscription<BatteryState> _batteryStateSubscription;

  late StreamSubscription<ConnectivityResult> _connectivitySubscription;
  String _networkStatus = "Recherche...";
  Color _networkColor = const Color(0xFF64748B);

  MethodChannel? _rtspChannel;
  bool _isStreaming = false;

  UsbDevice? _usbDevice;
  UsbPort? _usbPort;
  String _usbStatus = "Non connecté";
  Color _usbColor = const Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _initBattery();
    _initNetwork();
    
    // Connect to the global StreamManager channel instead of the view
    _rtspChannel = const MethodChannel('com.novawing/stream_manager');
    _rtspChannel!.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onConnectionStarted':
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Stream connecté: ${call.arguments}")));
          break;
        case 'onConnectionFailed':
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Échec stream: ${call.arguments}")));
          if (mounted) setState(() => _isStreaming = false);
          break;
        case 'onDisconnect':
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stream déconnecté")));
          if (mounted) setState(() => _isStreaming = false);
          break;
      }
    });
    _initUsb();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.microphone,
    ].request();
  }

  Future<void> _togglePreview() async {
    if (!_showPreview) {
      final statuses = await [
        Permission.camera,
        Permission.microphone,
      ].request();
      
      if (statuses[Permission.camera] != PermissionStatus.granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("L'autorisation de la caméra est requise."),
            backgroundColor: Colors.red,
          ));
        }
        return;
      }
    }
    setState(() {
      _showPreview = !_showPreview;
    });
  }

  void _initBattery() {
    _battery.batteryLevel.then((level) {
      if (mounted) setState(() => _phoneBatteryLevel = level);
    });
    _batteryStateSubscription = _battery.onBatteryStateChanged.listen((BatteryState state) {
      _battery.batteryLevel.then((level) {
        if (mounted) setState(() => _phoneBatteryLevel = level);
      });
    });
  }

  void _initNetwork() {
    Connectivity().checkConnectivity().then(_updateConnectionStatus);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    if (!mounted) return;
    setState(() {
      if (result == ConnectivityResult.mobile) {
        _networkStatus = "4G/5G Actif";
        _networkColor = const Color(0xFF00E5FF); // Neon Cyan
      } else if (result == ConnectivityResult.wifi) {
        _networkStatus = "WiFi Actif";
        _networkColor = const Color(0xFF00E676); // Neon Green
      } else {
        _networkStatus = "Hors ligne";
        _networkColor = const Color(0xFFFF1744); // Neon Red
      }
    });
  }

  void _initUsb() {
    UsbSerial.usbEventStream!.listen((UsbEvent event) {
      if (event.event == UsbEvent.ACTION_USB_ATTACHED) {
        _connectUsb(event.device);
      } else if (event.event == UsbEvent.ACTION_USB_DETACHED) {
        if (mounted) {
          setState(() {
            _usbStatus = "Déconnecté";
            _usbColor = const Color(0xFF64748B);
            _usbPort = null;
            _usbDevice = null;
          });
        }
      }
    });
    UsbSerial.listDevices().then((devices) {
      if (devices.isNotEmpty) _connectUsb(devices.first);
    });
  }

  Future<void> _connectUsb(UsbDevice? device) async {
    if (device == null) return;
    try {
      _usbPort = await device.create();
      bool openResult = await _usbPort!.open();
      if (!openResult) {
        if (mounted) {
          setState(() {
            _usbStatus = "Erreur accès";
            _usbColor = const Color(0xFFFF1744);
          });
        }
        return;
      }
      await _usbPort!.setDTR(true);
      await _usbPort!.setRTS(true);
      await _usbPort!.setPortParameters(57600, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);
      
      if (mounted) {
        setState(() {
          _usbDevice = device;
          _usbStatus = "Liaison 57600";
          _usbColor = const Color(0xFFFF9100); // Neon Orange
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _usbStatus = "Échec co.";
          _usbColor = const Color(0xFFFF1744);
        });
      }
    }
  }

  void _runPreFlightTest() {
    showDialog(
      context: _navigatorKey.currentContext!,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF121629),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFFFF9100), width: 2),
          ),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFFF9100), size: 32),
              SizedBox(width: 12),
              Text("TEST PRÉ-VOL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ],
          ),
          content: const Text(
            "ATTENTION : Cette procédure va faire bouger les gouvernes de l'aile et démarrer le moteur à 5% de sa puissance maximale.\n\nAssurez-vous que l'hélice est dégagée et que vous tenez fermement l'aile.",
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("ANNULER", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF1744),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _simulateTestSequence();
              },
              child: const Text("LANCER LE TEST", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _simulateTestSequence() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Séquence envoyée : Débattement Servos OK -> Moteur 5% OK", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF090B14))),
        backgroundColor: Color(0xFF00E676),
        duration: Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _ecoTimer?.cancel();
    _batteryStateSubscription.cancel();
    _connectivitySubscription.cancel();
    _rtspChannel?.invokeMethod('stopServer');
    _usbPort?.close();
    super.dispose();
  }

  void _enableEcoMode() {
    setState(() {
      _ecoModeEnabled = true;
      _ecoCountdown = 5;
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _ecoTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_ecoCountdown > 0) {
        setState(() => _ecoCountdown--);
      } else {
        timer.cancel();
      }
    });
  }

  void _disableEcoMode() {
    setState(() {
      _ecoModeEnabled = false;
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _ecoTimer?.cancel();
  }

  void _handleWakeUpTap() {
    final now = DateTime.now();
    if (_lastTapTime == null || now.difference(_lastTapTime!) > const Duration(milliseconds: 600)) {
      _tapCount = 1;
    } else {
      _tapCount++;
    }
    _lastTapTime = now;

    if (_tapCount >= 4) {
      _disableEcoMode();
      _tapCount = 0;
      _lastTapTime = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'NOVA 209',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090B14), 
        primaryColor: const Color(0xFF00E5FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF), 
          secondary: Color(0xFFFF9100), 
          surface: Color(0xFF121629), 
        ),
        fontFamily: 'Inter', 
        useMaterial3: true,
      ),
      home: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              backgroundColor: const Color(0xFF2A3457), // Couleur TRÈS différente (bleu acier/violet)
              surfaceTintColor: Colors.transparent, // Empêche le changement de couleur au scroll
              scrolledUnderElevation: 10, // Garde l'ombre au scroll
              elevation: 10,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(30.0)),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.flight_takeoff, color: Color(0xFF00E5FF)),
                  const SizedBox(width: 12),
                  Text(
                    'NOVA 209',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
              centerTitle: true,
            ),
            body: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _currentIndex == 0 ? _buildHomeScreen() : _buildRelayScreen(),
            ),
            floatingActionButton: _buildEcoButton(),
            floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
            bottomNavigationBar: _buildBottomNav(),
          ),
          
          if (_ecoModeEnabled)
            GestureDetector(
              onTap: _handleWakeUpTap,
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Colors.black, 
                  child: _ecoCountdown > 0
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.shield_moon, color: Colors.white70, size: 64),
                              const SizedBox(height: 24),
                              const Text(
                                "Appuyez 4 fois pour sortir",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white, 
                                  fontSize: 16, 
                                  letterSpacing: 1.0,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 32),
                              Text(
                                "$_ecoCountdown",
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFFF9100), 
                                  fontSize: 120, 
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEcoButton() {
    return SizedBox(
      width: 72,
      height: 72,
      child: FloatingActionButton(
        onPressed: _enableEcoMode,
        backgroundColor: const Color(0xFF00E676),
        elevation: 8,
        shape: const CircleBorder(),
        child: const Icon(Icons.power_settings_new, color: Color(0xFF090B14), size: 36),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomAppBar(
      color: const Color(0xFF2A3457), // Même couleur très distincte
      shape: const AutomaticNotchedShape(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
        ),
        CircleBorder(), // CircleBorder est le bon ShapeBorder invité (guest)
      ),
      clipBehavior: Clip.antiAlias,
      notchMargin: 12.0,
      elevation: 20,
      height: 85, // Enforce sufficient height to prevent overflow
      padding: EdgeInsets.zero, // Remove M3 default padding
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(0, Icons.speed, "VOL"),
          const SizedBox(width: 48), // Espace pour l'encoche au centre
          _buildNavItem(1, Icons.settings_ethernet, "RELAIS"),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: isSelected ? const Color(0xFF00E5FF) : const Color(0xFF64748B)),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(
              color: isSelected ? const Color(0xFF00E5FF) : const Color(0xFF64748B),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            )),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // ÉCRAN 1 : ACCUEIL (TABLEAU DE BORD)
  // ==========================================
  Widget _buildHomeScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _buildModernStatusCard(Icons.cell_tower, "RÉSEAU", _networkStatus, _networkColor)),
              const SizedBox(width: 16),
              Expanded(child: _buildModernStatusCard(Icons.usb, "FC MATEK", _usbStatus, _usbColor)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildModernStatusCard(Icons.smartphone, "BATTERIE TÉL", "$_phoneBatteryLevel%", _phoneBatteryLevel > 20 ? const Color(0xFF00E676) : const Color(0xFFFF1744))),
              const SizedBox(width: 16),
              Expanded(child: _buildModernStatusCard(Icons.bolt, "BATTERIE FC", "-- V", const Color(0xFFFF9100))),
            ],
          ),
          const SizedBox(height: 24),
          _buildModernContainer(
            title: "TÉLÉMÉTRIE & NAVIGATION",
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildHudElement("MODE", "N/A", "", Icons.flight, const Color(0xFF00E676))),
                    const SizedBox(width: 12),
                    Expanded(child: _buildHudElement("GPS", "--", "Sats", Icons.satellite_alt, const Color(0xFF00E5FF))),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildHudElement("VITESSE", "--", "km/h", Icons.speed, const Color(0xFFFF9100))),
                    const SizedBox(width: 12),
                    Expanded(child: _buildHudElement("ALTITUDE", "--", "m", Icons.height, const Color(0xFFD500F9))),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildHudElement("CAP (HDG)", "--", "°", Icons.explore, const Color(0xFF00E5FF))),
                    const SizedBox(width: 12),
                    Expanded(child: _buildHudElement("DISTANCE", "--", "m", Icons.social_distance, const Color(0xFFFF9100))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildModernContainer(
            title: "DYNAMIQUE DE VOL (IMU)",
            child: Row(
              children: [
                Expanded(child: _buildAttitudeElement("TANGAGE", "--", "°", Icons.flight_takeoff, const Color(0xFF00E676))),
                Container(width: 1, height: 50, color: Colors.white.withOpacity(0.1)),
                Expanded(child: _buildAttitudeElement("ROULIS", "--", "°", Icons.sync, const Color(0xFF00E5FF))),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildModernContainer(
            title: "TRAFIC DONNÉES",
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildDataNode("UPLINK TX", Icons.upload, "0", "kbps", const Color(0xFF00E5FF)),
                Container(width: 1, height: 60, color: Colors.white.withOpacity(0.1)),
                _buildDataNode("DOWNLINK RX", Icons.download, "0", "kbps", const Color(0xFFFF9100)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _runPreFlightTest,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9100).withOpacity(0.1),
                foregroundColor: const Color(0xFFFF9100),
                side: const BorderSide(color: Color(0xFFFF9100), width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              icon: const Icon(Icons.warning_rounded, size: 28),
              label: const Text("TEST PRÉ-VOL (SERVOS & MOTEUR 5%)", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0, fontSize: 12)),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildModernStatusCard(IconData icon, String title, String value, Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121629),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(color: accentColor.withOpacity(0.05), blurRadius: 10, spreadRadius: 1),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accentColor, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title, 
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value, 
            style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w900, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildHudElement(String label, String value, String unit, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF090B14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color.withOpacity(0.7), size: 16),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(width: 4),
              if (unit.isNotEmpty)
                Text(unit, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttitudeElement(String label, String value, String unit, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color.withOpacity(0.5), size: 28),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(width: 2),
            Text(unit, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      ],
    );
  }

  void _showCodecInfoDialog() {
    showDialog(
      context: _navigatorKey.currentContext!,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF121629),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
          title: Row(
            children: const [
              Icon(Icons.info_outline, color: Color(0xFF00E5FF)),
              SizedBox(width: 12),
              Text("Informations Codec", style: TextStyle(color: Colors.white)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("H.265 (HEVC)", style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                const Text("Meilleure qualité pour un même débit. Idéal pour limiter la consommation de données, notamment en 4G.", style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 24),
                const Text("H.264 (AVC)", style: TextStyle(color: Color(0xFFFF9100), fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                const Text("Plus compatible et moins exigeant pour le téléphone. À privilégier en cas de surchauffe ou de latence avec le H.265.", style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("FERMER", style: TextStyle(color: Color(0xFF00E5FF))),
            ),
          ],
        );
      },
    );
  }

  void _showBitrateModeInfoDialog() {
    showDialog(
      context: _navigatorKey.currentContext!,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF121629),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
          title: Row(
            children: const [
              Icon(Icons.info_outline, color: Color(0xFF00E5FF)),
              SizedBox(width: 12),
              Text("Mode de Débit", style: TextStyle(color: Colors.white)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("CBR (Constant Bitrate)", style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                const Text("Maintient un débit fixe. Idéal pour garantir la stabilité sur des réseaux (comme la 4G) où la bande passante est prévisible.", style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 24),
                const Text("VBR (Variable Bitrate)", style: TextStyle(color: Color(0xFFFF9100), fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                const Text("Ajuste le débit selon la complexité de l'image. Permet d'économiser de la bande passante quand l'image bouge peu, mais peut créer des pics.", style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 24),
                const Text("CQ (Constant Quality)", style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                const Text("Garantit une qualité d'image constante, sans se soucier du débit. À utiliser uniquement sur des réseaux excellents.", style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("FERMER", style: TextStyle(color: Color(0xFF00E5FF))),
            ),
          ],
        );
      },
    );
  }

  void _showTransportInfoDialog() {
    showDialog(
      context: _navigatorKey.currentContext!,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF121629),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
          title: Row(
            children: const [
              Icon(Icons.info_outline, color: Color(0xFF00E5FF)),
              SizedBox(width: 12),
              Expanded(child: Text("Format de Transport", style: TextStyle(color: Colors.white, fontSize: 16))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Option A : RTSP (Le plus simple)", style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                const Text("C'est le standard pour le streaming IP. Ton application Android agit comme un serveur RTSP auquel ta station au sol se connecte.\n\nAvantage : Facile à mettre en œuvre.\nInconvénient : Latence légèrement plus élevée que le WebRTC (200 à 400ms de retard).", style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 24),
                const Text("Option B : WebRTC (Le plus performant)", style: TextStyle(color: Color(0xFFFF9100), fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                const Text("C'est la technologie utilisée par les navigateurs web pour les visioconférences.\n\nAvantage : Offre la latence la plus faible possible (sous les 150ms) et gère mieux les pertes de paquets.\nInconvénient : Beaucoup plus complexe à programmer sur Android.", style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("FERMER", style: TextStyle(color: Color(0xFF00E5FF))),
            ),
          ],
        );
      },
    );
  }

  void _showBitrateInfoDialog() {
    showDialog(
      context: _navigatorKey.currentContext!,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF121629),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
          title: Row(
            children: const [
              Icon(Icons.info_outline, color: Color(0xFF00E5FF)),
              SizedBox(width: 12),
              Expanded(child: Text("Paramètres d'Encodage", style: TextStyle(color: Colors.white, fontSize: 16))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("3. Les Paramètres d'Encodage (Bitrate, Résolution, FPS)", style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 16),
                const Text("C'est ici que tu règles le curseur pour que le flux passe en 4G. Si tu mets trop haut, l'image fige.", style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("FERMER", style: TextStyle(color: Color(0xFF00E5FF))),
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // ÉCRAN 2 : RELAIS & CONFIGURATION
  // ==========================================
  Widget _buildRelayScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildModernContainer(
            title: "CONNEXION GCS DISTANTE",
            child: Column(
              children: [
                Column(
                  children: [
                    _buildNeonTextField("IP SERVEUR", "192.168.1.100", Icons.dns, initialValue: _serverIp, onChanged: (val) => setState(() => _serverIp = val)),
                    const SizedBox(height: 16),
                    _buildNeonTextField("PORT", "14550", Icons.settings_input_component, initialValue: _serverPort, onChanged: (val) => setState(() => _serverPort = val)),
                    const SizedBox(height: 16),
                    _buildNeonTextField("KEY", "Clé serveur", Icons.vpn_key, initialValue: _serverToken, onChanged: (val) => setState(() => _serverToken = val)),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_rtspChannel != null) {
                        if (_isStreaming) {
                          _rtspChannel!.invokeMethod('stopServer');
                          setState(() => _isStreaming = false);
                        } else {
                          if (_serverToken.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Erreur: La clé (KEY) serveur est requise pour sécuriser la liaison.", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                backgroundColor: Color(0xFFFF1744),
                                duration: Duration(seconds: 3),
                              ),
                            );
                            return;
                          }
                          _rtspChannel!.invokeMethod('startServer', {
                            'bitrate': _videoBitrate,
                            'codec': _selectedCodec,
                            'resolution': _selectedResolution,
                            'fps': _selectedFps,
                            'bitrateMode': _selectedBitrateMode,
                            'token': _serverToken.trim(),
                            'ip': _serverIp,
                            'port': _serverPort,
                          });
                          setState(() => _isStreaming = true);
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isStreaming ? const Color(0xFFFF1744) : const Color(0xFF00E676),
                      foregroundColor: const Color(0xFF090B14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 10,
                      shadowColor: (_isStreaming ? const Color(0xFFFF1744) : const Color(0xFF00E676)).withOpacity(0.5),
                    ),
                    child: Text(_isStreaming ? "ARRÊTER LA LIAISON" : "INITIALISER LA LIAISON", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildModernContainer(
            title: "RÉGLAGES D'ENCODAGE",
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text("CODEC : H.264 ", style: TextStyle(color: _selectedCodec == "H.264" ? const Color(0xFF00E676) : Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                        Switch(
                          value: _selectedCodec == "H.265",
                          onChanged: (bool value) {
                            setState(() {
                              _selectedCodec = value ? "H.265" : "H.264";
                            });
                          },
                          activeColor: const Color(0xFF00E5FF),
                          activeTrackColor: const Color(0xFF00E5FF).withOpacity(0.3),
                          inactiveThumbColor: const Color(0xFF00E676),
                          inactiveTrackColor: const Color(0xFF00E676).withOpacity(0.3),
                        ),
                        Text(" H.265", style: TextStyle(color: _selectedCodec == "H.265" ? const Color(0xFF00E5FF) : Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.info_outline, color: Colors.white54),
                      onPressed: _showCodecInfoDialog,
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text("PROTOCOLE : RTSP ", style: TextStyle(color: _selectedProtocol == "RTSP" ? const Color(0xFF00E676) : Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                        Switch(
                          value: _selectedProtocol == "WebRTC",
                          onChanged: (bool value) {
                            setState(() {
                              _selectedProtocol = value ? "WebRTC" : "RTSP";
                            });
                          },
                          activeColor: const Color(0xFFFF9100),
                          activeTrackColor: const Color(0xFFFF9100).withOpacity(0.3),
                          inactiveThumbColor: const Color(0xFF00E676),
                          inactiveTrackColor: const Color(0xFF00E676).withOpacity(0.3),
                        ),
                        Text(" WebRTC", style: TextStyle(color: _selectedProtocol == "WebRTC" ? const Color(0xFFFF9100) : Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.info_outline, color: Colors.white54),
                      onPressed: _showTransportInfoDialog,
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("DÉBIT MAX (4G) : ${_videoBitrate.toStringAsFixed(1)} Mbps", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.info_outline, color: Colors.white54),
                      onPressed: _showBitrateInfoDialog,
                    ),
                  ],
                ),
                Slider(
                  value: _videoBitrate,
                  min: 0.5,
                  max: 10.0,
                  divisions: 19,
                  activeColor: const Color(0xFF00E5FF),
                  inactiveColor: Colors.white12,
                  onChanged: (value) {
                    setState(() {
                      _videoBitrate = value;
                    });
                  },
                ),
                const Divider(color: Colors.white12, height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("RÉSOLUTION", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                    DropdownButton<String>(
                      value: _selectedResolution,
                      dropdownColor: const Color(0xFF1C1E26),
                      style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 12),
                      underline: const SizedBox(),
                      items: ["480p", "720p", "1080p"].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        setState(() => _selectedResolution = newValue!);
                      },
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("FPS (IMAGES/SEC)", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                    DropdownButton<int>(
                      value: _selectedFps,
                      dropdownColor: const Color(0xFF1C1E26),
                      style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 12),
                      underline: const SizedBox(),
                      items: [15, 24, 30, 60].map((int value) {
                        return DropdownMenuItem<int>(
                          value: value,
                          child: Text("$value fps"),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        setState(() => _selectedFps = newValue!);
                      },
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text("MODE DE DÉBIT ", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.info_outline, color: Colors.white54, size: 16),
                          onPressed: _showBitrateModeInfoDialog,
                        ),
                      ],
                    ),
                    DropdownButton<String>(
                      value: _selectedBitrateMode,
                      dropdownColor: const Color(0xFF1C1E26),
                      style: const TextStyle(color: Color(0xFFFF9100), fontWeight: FontWeight.bold, fontSize: 12),
                      underline: const SizedBox(),
                      items: ["CBR", "VBR", "CQ"].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        setState(() => _selectedBitrateMode = newValue!);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildModernContainer(
            title: "FLUX VIDÉO EMBARQUÉ",
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _togglePreview,
                    icon: Icon(_showPreview ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF00E5FF)),
                    label: Text(_showPreview ? "MASQUER L'AFFICHAGE" : "TESTER L'AFFICHAGE", style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2A3457),
                      foregroundColor: const Color(0xFF00E5FF),
                      side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                if (_showPreview) ...[
                  const SizedBox(height: 16),
                  Container(
                    height: 220,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3), width: 2),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.1), blurRadius: 10, spreadRadius: 2),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: const RtspCameraWidget(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 80), 
        ],
      ),
    );
  }

  Widget _buildModernContainer({required String title, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121629),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Text(
              title,
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2.0),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildNeonTextField(String label, String hint, IconData icon, {String? initialValue, ValueChanged<String>? onChanged}) {
    return TextFormField(
      initialValue: initialValue,
      onChanged: onChanged,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.bold, letterSpacing: 1.0),
        prefixIcon: Icon(icon, color: const Color(0xFF00E5FF)),
        filled: true,
        fillColor: const Color(0xFF090B14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 2),
        ),
      ),
    );
  }

  Widget _buildDataNode(String label, IconData icon, String value, String unit, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(width: 4),
            Text(unit, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
      ],
    );
  }
}
