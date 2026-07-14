import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const AsconaReturnsApp());
}

class AsconaReturnsApp extends StatelessWidget {
  const AsconaReturnsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ASCONA Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF155EEF)),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: Color(0xFFD8DEE6)),
          ),
        ),
      ),
      home: const ReturnsHomePage(),
    );
  }
}

enum ScanTarget { returnCode, itemCode }

class ReturnRecord {
  ReturnRecord({
    required this.id,
    required this.createdAt,
    required this.marketplace,
    required this.operatorName,
    required this.shift,
    required this.returnCode,
    required this.itemCode,
    required this.itemName,
    required this.condition,
    required this.comment,
  });

  final String id;
  final DateTime createdAt;
  final String marketplace;
  final String operatorName;
  final String shift;
  final String returnCode;
  final String itemCode;
  final String itemName;
  final String condition;
  final String comment;

  bool get hasProblem => condition != 'Принят';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'marketplace': marketplace,
      'operatorName': operatorName,
      'shift': shift,
      'returnCode': returnCode,
      'itemCode': itemCode,
      'itemName': itemName,
      'condition': condition,
      'comment': comment,
    };
  }

  factory ReturnRecord.fromJson(Map<String, dynamic> json) {
    return ReturnRecord(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      marketplace: json['marketplace'] as String? ?? 'OZON',
      operatorName: json['operatorName'] as String? ?? '',
      shift: json['shift'] as String? ?? 'День',
      returnCode: json['returnCode'] as String? ?? '',
      itemCode: json['itemCode'] as String? ?? '',
      itemName: json['itemName'] as String? ?? '',
      condition: json['condition'] as String? ?? 'Принят',
      comment: json['comment'] as String? ?? '',
    );
  }

  ReturnRecord copyWith({
    String? marketplace,
    String? operatorName,
    String? shift,
    String? returnCode,
    String? itemCode,
    String? itemName,
    String? condition,
    String? comment,
  }) {
    return ReturnRecord(
      id: id,
      createdAt: createdAt,
      marketplace: marketplace ?? this.marketplace,
      operatorName: operatorName ?? this.operatorName,
      shift: shift ?? this.shift,
      returnCode: returnCode ?? this.returnCode,
      itemCode: itemCode ?? this.itemCode,
      itemName: itemName ?? this.itemName,
      condition: condition ?? this.condition,
      comment: comment ?? this.comment,
    );
  }
}

class ReturnsHomePage extends StatefulWidget {
  const ReturnsHomePage({super.key});

  @override
  State<ReturnsHomePage> createState() => _ReturnsHomePageState();
}

class _ReturnsHomePageState extends State<ReturnsHomePage> {
  static const _recordsKey = 'return_records';
  static const _settingsKey = 'return_settings';

  final _operatorController = TextEditingController();
  final _returnCodeController = TextEditingController();
  final _itemCodeController = TextEditingController();
  final _itemNameController = TextEditingController();
  final _commentController = TextEditingController();
  final _manualCodeController = TextEditingController();
  final _imagePicker = ImagePicker();

  List<ReturnRecord> _records = [];
  String _marketplace = 'OZON';
  String _shift = 'День';
  String _condition = 'Принят';
  bool _compactMode = true;
  bool _cameraPermissionDenied = false;
  bool _codeTargetDialogOpen = false;
  bool _barcodeScanBusy = false;
  bool _ocrBusy = false;
  String? _editingId;

  final _marketplaces = ['OZON', 'Wildberries', 'Яндекс Маркет', 'Другой'];
  final _shifts = ['День', 'Ночь', '1 смена', '2 смена'];
  final _conditions = [
    'Принят',
    'Брак',
    'Не тот товар',
    'Некомплект',
    'Не читается код',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _operatorController.dispose();
    _returnCodeController.dispose();
    _itemCodeController.dispose();
    _itemNameController.dispose();
    _commentController.dispose();
    _manualCodeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final recordsRaw = prefs.getString(_recordsKey);
    final settingsRaw = prefs.getString(_settingsKey);

    if (recordsRaw != null && recordsRaw.isNotEmpty) {
      final list = jsonDecode(recordsRaw) as List<dynamic>;
      _records = list
          .map((item) => ReturnRecord.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    if (settingsRaw != null && settingsRaw.isNotEmpty) {
      final settings = jsonDecode(settingsRaw) as Map<String, dynamic>;
      _operatorController.text = settings['operatorName'] as String? ?? '';
      _marketplace = settings['marketplace'] as String? ?? _marketplace;
      _shift = settings['shift'] as String? ?? _shift;
      _condition = settings['condition'] as String? ?? _condition;
      _compactMode = settings['compactMode'] as bool? ?? _compactMode;
    }

    if (mounted) setState(() {});
  }

  Future<void> _saveRecords() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _recordsKey,
      jsonEncode(_records.map((record) => record.toJson()).toList()),
    );
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _settingsKey,
      jsonEncode({
        'operatorName': _operatorController.text.trim(),
        'marketplace': _marketplace,
        'shift': _shift,
        'condition': _condition,
        'compactMode': _compactMode,
      }),
    );
  }

  Future<void> _handleScannedCode(String code) async {
    final clean = code.trim();
    if (clean.isEmpty) return;
    if (_codeTargetDialogOpen) return;

    _codeTargetDialogOpen = true;
    if (!mounted) {
      _codeTargetDialogOpen = false;
      return;
    }

    final target = await showDialog<ScanTarget>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Куда вставить код?'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(clean),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ScanTarget.returnCode),
            child: const Text('В код возврата / заказа'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ScanTarget.itemCode),
            child: const Text('В код товара'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );

    _codeTargetDialogOpen = false;
    if (!mounted || target == null) return;

    setState(() {
      if (target == ScanTarget.returnCode) {
        _returnCodeController.text = clean;
      } else {
        _itemCodeController.text = clean;
      }
    });
  }

  Future<void> _scanCodeFromPhoto() async {
    if (_barcodeScanBusy) return;
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _cameraPermissionDenied = true;
      });
      _showMessage('Разрешите доступ к камере в настройках Android');
      return;
    }

    if (!mounted) return;
    setState(() {
      _cameraPermissionDenied = false;
      _barcodeScanBusy = true;
    });

    final scanner = MobileScannerController(autoStart: false);
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );
      if (image == null) return;

      final capture = await scanner.analyzeImage(image.path);
      final codes = capture?.barcodes
              .map((barcode) => barcode.rawValue ?? barcode.displayValue ?? '')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList() ??
          <String>[];

      if (!mounted) return;
      if (codes.isEmpty) {
        _showMessage('Код не найден. Сфотографируйте ближе и без бликов');
        return;
      }

      final code = codes.length == 1 ? codes.first : await _chooseDetectedCode(codes);
      if (code != null) await _handleScannedCode(code);
    } catch (error) {
      if (mounted) _showMessage('Не удалось распознать код: $error');
    } finally {
      await scanner.dispose();
      if (mounted) setState(() => _barcodeScanBusy = false);
    }
  }

  Future<String?> _chooseDetectedCode(List<String> codes) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Выберите найденный код'),
        children: [
          for (final code in codes)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, code),
              child: Text(code),
            ),
        ],
      ),
    );
  }

  Future<void> _recognizeTextFromCamera() async {
    if (_ocrBusy) return;
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _cameraPermissionDenied = true);
      _showMessage('Разрешите доступ к камере в настройках Android');
      return;
    }

    if (!mounted) return;
    setState(() => _ocrBusy = true);
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
      if (image == null) return;

      final croppedImage = await ImageCropper().cropImage(
        sourcePath: image.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 95,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Выделите нужный текст',
            toolbarColor: const Color(0xFF155EEF),
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: const Color(0xFF155EEF),
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
        ],
      );
      if (croppedImage == null) return;

      final recognizedText = await FlutterTesseractOcr.extractText(
        croppedImage.path,
        language: 'rus+eng',
        args: {
          'oem': '1',
          'psm': '6',
          'preserve_interword_spaces': '1',
        },
      );
      final recognizedLines = recognizedText
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where(_isUsefulRecognizedLine)
          .toSet()
          .toList();
      final fullText = recognizedLines.join(' ');
      final suggestedLines = [...recognizedLines]
        ..sort((a, b) => _recognizedLineScore(b).compareTo(_recognizedLineScore(a)));

      if (!mounted) return;
      if (recognizedLines.isEmpty) {
        _showMessage('Текст не распознан. Попробуйте ближе и при хорошем свете');
        return;
      }
      _showRecognizedTextSheet(suggestedLines, fullText);
    } catch (error) {
      if (!mounted) return;
      _showMessage('Не удалось распознать текст: $error');
    } finally {
      if (mounted) setState(() => _ocrBusy = false);
    }
  }

  bool _isUsefulRecognizedLine(String line) {
    if (line.length < 2) return false;
    final meaningful = RegExp(r'[A-Za-zА-Яа-яЁё0-9]').allMatches(line).length;
    return meaningful >= 2 && meaningful / line.length >= 0.35;
  }

  int _recognizedLineScore(String line) {
    final cyrillic = RegExp(r'[А-Яа-яЁё]').allMatches(line).length;
    final digits = RegExp(r'[0-9]').allMatches(line).length;
    final normalized = line.toLowerCase();
    const keywords = [
      'артикул',
      'наименование',
      'состав',
      'цвет',
      'размер',
      'изготовитель',
      'производитель',
      'дата',
      'страна',
    ];
    final keywordBonus = keywords.any((keyword) => normalized.contains(keyword)) ? 80 : 0;
    return keywordBonus + cyrillic * 4 + digits + line.length.clamp(0, 40).toInt();
  }

  void _showRecognizedTextSheet(List<String> lines, String fullText) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(
                'Распознанный текст',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Вставьте весь выделенный текст в наименование или выберите отдельную строку.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _reviewAndInsertFullText(fullText),
                icon: const Icon(Icons.playlist_add_check),
                label: const Text('Вставить весь текст в наименование'),
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 4),
              Text(
                'Отдельные строки',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final line in lines)
                Card(
                  child: ListTile(
                    title: Text(line),
                    subtitle: const Text('Вставить в поле'),
                    onTap: () => _showPasteTargetDialog(line),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _reviewAndInsertFullText(String text) async {
    final controller = TextEditingController(text: text);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Проверьте наименование'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 7,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Исправьте ошибки распознавания при необходимости',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Вставить'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (!mounted || result == null || result.isEmpty) return;
    setState(() => _itemNameController.text = result);
    Navigator.pop(context);
  }

  Future<void> _showPasteTargetDialog(String text) async {
    final target = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Куда вставить?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'returnCode'),
            child: const Text('Код возврата / заказа'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'itemCode'),
            child: const Text('Код товара'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'itemName'),
            child: const Text('Наименование товара'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'comment'),
            child: const Text('Комментарий'),
          ),
        ],
      ),
    );

    if (target == null) return;
    setState(() {
      switch (target) {
        case 'returnCode':
          _returnCodeController.text = text;
          break;
        case 'itemCode':
          _itemCodeController.text = text;
          break;
        case 'itemName':
          _itemNameController.text = text;
          break;
        case 'comment':
          final current = _commentController.text.trim();
          _commentController.text = current.isEmpty ? text : '$current\n$text';
          break;
      }
    });
    if (mounted) Navigator.pop(context);
  }

  Future<void> _saveReturn() async {
    final returnCode = _returnCodeController.text.trim();
    if (returnCode.isEmpty) {
      _showMessage('Сначала укажите код возврата или заказа');
      return;
    }

    final record = ReturnRecord(
      id: _editingId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt: _editingId == null
          ? DateTime.now()
          : _records.firstWhere((item) => item.id == _editingId).createdAt,
      marketplace: _marketplace,
      operatorName: _operatorController.text.trim(),
      shift: _shift,
      returnCode: returnCode,
      itemCode: _itemCodeController.text.trim(),
      itemName: _itemNameController.text.trim(),
      condition: _condition,
      comment: _commentController.text.trim(),
    );

    setState(() {
      if (_editingId == null) {
        _records.insert(0, record);
      } else {
        _records = _records
            .map((item) => item.id == _editingId ? record : item)
            .toList();
        _editingId = null;
      }
      _clearForm(keepReturn: true);
    });

    await _saveSettings();
    await _saveRecords();
    _showMessage('Возврат зафиксирован');
  }

  void _clearForm({bool keepReturn = false}) {
    if (!keepReturn) _returnCodeController.clear();
    _itemCodeController.clear();
    _itemNameController.clear();
    _commentController.clear();
    if (!_compactMode) {
      _condition = 'Принят';
    }
  }

  void _editRecord(ReturnRecord record) {
    setState(() {
      _editingId = record.id;
      _marketplace = record.marketplace;
      _shift = record.shift;
      _condition = record.condition;
      _operatorController.text = record.operatorName;
      _returnCodeController.text = record.returnCode;
      _itemCodeController.text = record.itemCode;
      _itemNameController.text = record.itemName;
      _commentController.text = record.comment;
    });
  }

  Future<void> _deleteRecord(ReturnRecord record) async {
    setState(() {
      _records.removeWhere((item) => item.id == record.id);
    });
    await _saveRecords();
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить журнал?'),
        content: const Text('Все записи возвратов на этом устройстве будут удалены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _records.clear());
    await _saveRecords();
  }

  Future<void> _exportCsv() async {
    final buffer = StringBuffer();
    buffer.writeln(
      [
        'Дата',
        'Маркетплейс',
        'Смена',
        'Сотрудник',
        'Код возврата',
        'Код товара',
        'Наименование',
        'Состояние',
        'Комментарий',
      ].map(_csv).join(';'),
    );

    for (final record in _records) {
      buffer.writeln(
        [
          _formatDateTime(record.createdAt),
          record.marketplace,
          record.shift,
          record.operatorName,
          record.returnCode,
          record.itemCode,
          record.itemName,
          record.condition,
          record.comment,
        ].map(_csv).join(';'),
      );
    }

    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/ascona_returns_${DateTime.now().toIso8601String().substring(0, 10)}.csv',
    );
    await file.writeAsString('\ufeff${buffer.toString()}', encoding: utf8);
    await Share.shareXFiles([XFile(file.path)], text: 'ASCONA Scanner: отчет по возвратам');
  }

  String _csv(String value) => '"${value.replaceAll('"', '""')}"';

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  int get _accepted => _records.where((record) => !record.hasProblem).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ASCONA Scanner · Возвраты'),
        actions: [
          IconButton(
            tooltip: 'Экспорт CSV',
            onPressed: _records.isEmpty ? null : _exportCsv,
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _buildSummary(),
            const SizedBox(height: 12),
            _buildScannerCard(),
            const SizedBox(height: 12),
            _buildActionCard(),
            const SizedBox(height: 12),
            _buildPositionsCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    return Row(
      children: [
        Expanded(child: _MetricCard(label: 'Возвратов', value: '${_records.length}')),
        const SizedBox(width: 8),
        Expanded(child: _MetricCard(label: 'Принято', value: '$_accepted')),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricCard(
            label: 'Проблем',
            value: '${_records.length - _accepted}',
            warning: true,
          ),
        ),
      ],
    );
  }

  Widget _buildScannerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Сканирование кода',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Text('выбор после скана'),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 150,
                color: const Color(0xFF111827),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.qr_code_2, color: Colors.white, size: 46),
                    const SizedBox(height: 8),
                    Text(
                      _cameraPermissionDenied
                          ? 'Нет доступа к камере'
                          : _barcodeScanBusy
                              ? 'Поиск кода на фотографии...'
                              : 'Сканирование через штатную камеру',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _barcodeScanBusy ? null : _scanCodeFromPhoto,
                    icon: _barcodeScanBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt_outlined),
                    label: Text(
                      _barcodeScanBusy ? 'Распознавание кода...' : 'Сфотографировать штрихкод',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _ocrBusy ? null : _recognizeTextFromCamera,
              icon: _ocrBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.document_scanner_outlined),
              label: Text(
                _ocrBusy ? 'Распознавание...' : 'Сфотографировать и выделить текст',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Ручной ввод или сканер ТСД',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (value) {
                      _handleScannedCode(value);
                      _manualCodeController.clear();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    _handleScannedCode(_manualCodeController.text);
                    _manualCodeController.clear();
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Действия', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            TextField(
              controller: _operatorController,
              decoration: const InputDecoration(
                labelText: 'Сотрудник',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _saveSettings(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Dropdown(
                    label: 'Поставщик',
                    value: _marketplace,
                    values: _marketplaces,
                    onChanged: (value) {
                      setState(() => _marketplace = value);
                      _saveSettings();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Dropdown(
                    label: 'Смена',
                    value: _shift,
                    values: _shifts,
                    onChanged: (value) {
                      setState(() => _shift = value);
                      _saveSettings();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _Dropdown(
              label: 'Состояние',
              value: _condition,
              values: _conditions,
              onChanged: (value) {
                setState(() => _condition = value);
                _saveSettings();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _compactMode,
              onChanged: (value) {
                setState(() => _compactMode = value);
                _saveSettings();
              },
              title: const Text('Компактный режим'),
              subtitle: const Text('Сохранять поставщика и состояние для следующих позиций'),
            ),
            TextField(
              controller: _returnCodeController,
              decoration: const InputDecoration(
                labelText: 'Код возврата / заказа',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _itemCodeController,
              decoration: const InputDecoration(
                labelText: 'Код товара',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _itemNameController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Наименование товара',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _commentController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Комментарий',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saveReturn,
                    icon: const Icon(Icons.save),
                    label: Text(_editingId == null ? 'Зафиксировать возврат' : 'Сохранить исправление'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => setState(() => _clearForm()),
                  child: const Text('Очистить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Позиции', style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: _records.isEmpty ? null : _clearAll,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Очистить'),
                ),
              ],
            ),
            if (_records.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('Пока нет обработанных возвратов.'),
              )
            else
              ..._records.map(_buildRecordTile),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordTile(ReturnRecord record) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${record.returnCode} · ${record.itemCode.isEmpty ? 'товар не указан' : record.itemCode}'),
      subtitle: Text(
        [
          record.itemName,
          record.marketplace,
          record.condition,
          _formatDateTime(record.createdAt),
        ].where((item) => item.isNotEmpty).join(' · '),
      ),
      leading: CircleAvatar(
        backgroundColor: record.hasProblem ? Colors.orange.shade100 : Colors.green.shade100,
        child: Icon(
          record.hasProblem ? Icons.report_problem_outlined : Icons.check,
          color: record.hasProblem ? Colors.orange.shade800 : Colors.green.shade800,
        ),
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'Исправить',
            onPressed: () => _editRecord(record),
            icon: const Icon(Icons.edit),
          ),
          IconButton(
            tooltip: 'Удалить',
            onPressed: () => _deleteRecord(record),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}.${two(value.month)}.${value.year} ${two(value.hour)}:${two(value.minute)}';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    this.warning = false,
  });

  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: warning ? Colors.orange.shade800 : null,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: values
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}
