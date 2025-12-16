import 'dart:io';

import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:queue/queue.dart';
import 'package:window_manager/window_manager.dart';

import './i18n/strings.g.dart';
import './models/entry_info.dart';
import './models/unity_package_entry.dart';
import './services/zopflipng_options.dart';
import './services/png_compressor.dart';
import './services/unity_package_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LocaleSettings.useDeviceLocale();
  runApp(TranslationProvider(child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'multi zopflipng',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'multi zopflipng'),
      locale: TranslationProvider.of(context).flutterLocale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WindowListener {
  final Queue _queue = Queue(parallel: Platform.numberOfProcessors ~/ 2);
  final List<EntryInfo> _entries = [];
  final PngCompressor _pngCompressor = PngCompressor();
  final UnityPackageService _unityPackageService = UnityPackageService();

  bool _m = true;
  bool _lossyTransparent = false;
  bool _lossy8bit = false;
  bool _preserveExif = false;
  bool _preserveTextMetadata = true;
  bool _isStarted = false;
  int _sessionId = 0;

  ZopflipngOptions get _options => ZopflipngOptions(
        m: _m,
        lossyTransparent: _lossyTransparent,
        lossy8bit: _lossy8bit,
        preserveExif: _preserveExif,
        preserveTextMetadata: _preserveTextMetadata,
      );

  void _addEntries(DropDoneDetails details) async {
    var addEntries = <EntryInfo>[];
    for (var f in details.files) {
      if (await FileSystemEntity.isDirectory(f.path)) {
        await for (var ff in Directory(f.path).list(recursive: true)) {
          if (await FileSystemEntity.isFile(ff.path)) {
            final ext = p.extension(ff.path).toLowerCase();
            if (ext == ".png") {
              addEntries.add(PngEntryInfo(ff.path, await File(ff.path).length()));
            } else if (ext == ".unitypackage") {
              final entry = await _createUnityPackageEntry(ff.path);
              if (entry != null) addEntries.add(entry);
            }
          }
        }
      } else {
        final ext = p.extension(f.path).toLowerCase();
        if (ext == ".png") {
          addEntries.add(PngEntryInfo(f.path, await File(f.path).length()));
        } else if (ext == ".unitypackage") {
          final entry = await _createUnityPackageEntry(f.path);
          if (entry != null) addEntries.add(entry);
        }
      }
    }
    setState(() {
      _entries.addAll(addEntries);
    });
    if (_isStarted) {
      _enqueueEntries(addEntries);
    }
  }

  Future<UnityPackageEntry?> _createUnityPackageEntry(String path) async {
    try {
      final pngEntries = await _unityPackageService.scanPngEntries(path);
      if (pngEntries.isEmpty) return null;

      final fileSize = await File(path).length();
      return UnityPackageEntry(
        path: path,
        before: fileSize,
        pngEntries: pngEntries,
      );
    } catch (e) {
      // Failed to parse unitypackage, skip it
      return null;
    }
  }

  void _addFilesFromPicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'unitypackage'],
      allowMultiple: true,
    );
    if (result == null) return;

    var addEntries = <EntryInfo>[];
    for (var file in result.files) {
      if (file.path != null) {
        final ext = p.extension(file.path!).toLowerCase();
        if (ext == ".png") {
          addEntries.add(PngEntryInfo(file.path!, await File(file.path!).length()));
        } else if (ext == ".unitypackage") {
          final entry = await _createUnityPackageEntry(file.path!);
          if (entry != null) addEntries.add(entry);
        }
      }
    }
    setState(() {
      _entries.addAll(addEntries);
    });
    if (_isStarted) {
      _enqueueEntries(addEntries);
    }
  }

  void _addFolderFromPicker() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null) return;

    var addEntries = <EntryInfo>[];
    await for (var file in Directory(result).list(recursive: true)) {
      if (await FileSystemEntity.isFile(file.path)) {
        final ext = p.extension(file.path).toLowerCase();
        if (ext == ".png") {
          addEntries.add(PngEntryInfo(file.path, await File(file.path).length()));
        } else if (ext == ".unitypackage") {
          final entry = await _createUnityPackageEntry(file.path);
          if (entry != null) addEntries.add(entry);
        }
      }
    }
    setState(() {
      _entries.addAll(addEntries);
    });
    if (_isStarted) {
      _enqueueEntries(addEntries);
    }
  }

  void _enqueueEntries(List<EntryInfo> entries) {
    final currentSession = _sessionId;
    for (var e in entries) {
      if (e is PngEntryInfo) {
        _enqueuePngEntry(e, currentSession);
      } else if (e is UnityPackageEntry) {
        _enqueueUnityPackageEntry(e, currentSession);
      }
    }
  }

  void _enqueuePngEntry(PngEntryInfo e, int currentSession) {
    _queue.add(() async {
      if (currentSession != _sessionId) return;

      setState(() {
        e.processing = true;
      });

      final result = await _pngCompressor.compress(e.path, _options);

      if (currentSession != _sessionId) return;

      setState(() {
        e.processing = false;
        if (result.success) {
          e.after = result.newSize;
        }
      });
    });
  }

  void _enqueueUnityPackageEntry(UnityPackageEntry pkg, int currentSession) {
    for (var pngEntry in pkg.pngEntries) {
      // Skip already processed entries
      if (pngEntry.isProcessed || pngEntry.processing) continue;

      _queue.add(() async {
        if (currentSession != _sessionId) return;

        setState(() {
          pngEntry.processing = true;
        });

        try {
          // Extract PNG to temp file
          final tempPath = await _unityPackageService.extractPngToTemp(
            pkg.path,
            pngEntry,
          );
          pngEntry.tempFilePath = tempPath;

          // Compress the temp file
          final result = await _pngCompressor.compress(tempPath, _options);

          if (currentSession != _sessionId) return;

          setState(() {
            pngEntry.processing = false;
            if (result.success) {
              pngEntry.after = result.newSize;
            }
          });

          // Check if all PNGs are processed and repackage
          _checkAndRepackage(pkg, currentSession);
        } catch (e) {
          if (currentSession != _sessionId) return;
          setState(() {
            pngEntry.processing = false;
          });
        }
      });
    }

    // Also check if already all processed (resuming after stop)
    _checkAndRepackage(pkg, currentSession);
  }

  void _checkAndRepackage(UnityPackageEntry pkg, int currentSession) {
    if (!pkg.allPngsProcessed) return;
    if (pkg.processing) return; // Already repackaging

    _queue.add(() async {
      if (currentSession != _sessionId) return;

      setState(() {
        pkg.processing = true;
      });

      try {
        final newSize = await _unityPackageService.repackage(
          pkg.path,
          pkg.pngEntries,
        );

        if (currentSession != _sessionId) return;

        setState(() {
          pkg.processing = false;
          pkg.after = newSize;
        });

        // Cleanup temp files
        await _unityPackageService.cleanupTempFiles(pkg.pngEntries);
      } catch (e) {
        if (currentSession != _sessionId) return;
        setState(() {
          pkg.processing = false;
        });
      }
    });
  }

  void _startProcessing() {
    setState(() {
      _isStarted = true;
    });
    var pendingEntries =
        _entries.where((e) => !e.isProcessed && !e.processing).toList();
    _enqueueEntries(pendingEntries);
  }

  void _stopProcessing() {
    _sessionId++;
    _pngCompressor.killAll();

    setState(() {
      _isStarted = false;
      for (var e in _entries) {
        if (e.processing) {
          e.processing = false;
        }
        // Reset processing flag on child entries, but keep processed state
        if (e is UnityPackageEntry) {
          for (var child in e.pngEntries) {
            if (child.processing) {
              child.processing = false;
            }
          }
        }
      }
    });
    // Note: temp files are kept for resume capability
  }

  String _title() {
    if (_entries.isEmpty) {
      return "ready";
    }
    var processedEntries =
        _entries.where((e) => e.isProcessed).toList(growable: false);
    var totalBefore = _entries.fold(0, (p, e) => p + e.before);
    var before = processedEntries.fold(0, (p, e) => p + e.before);
    var after = processedEntries.fold(0, (p, e) => p + e.after!);
    var reduced = before - after;
    var reducedRate = before == 0 ? 0 : reduced / before;
    var reducedPercent = (reducedRate * 100).toStringAsFixed(2);
    return "${processedEntries.length} / ${_entries.length} | ${t.result}: ${filesize(totalBefore)} ${filesize(before)} -> ${filesize(after)} (-${filesize(reduced)} / $reducedPercent%)";
  }

  /// Display item for the list view
  List<_DisplayItem> _buildDisplayList() {
    final items = <_DisplayItem>[];
    for (final e in _entries) {
      if (e is PngEntryInfo) {
        items.add(_DisplayItem(entry: e, indent: 0));
      } else if (e is UnityPackageEntry) {
        items.add(_DisplayItem(entry: e, indent: 0, isUnityPackage: true));
        for (final child in e.pngEntries) {
          items.add(_DisplayItem(entry: child, indent: 1));
        }
      }
    }
    return items;
  }

  Widget _buildEntryRow(_DisplayItem item) {
    final e = item.entry;

    Color? bgColor;
    if (e.processing) {
      bgColor = Colors.yellow;
    } else if (item.isUnityPackage) {
      // Check if any child is processing
      final pkg = e as UnityPackageEntry;
      if (pkg.pngEntries.any((child) => child.processing)) {
        bgColor = Colors.yellow.shade100;
      } else {
        bgColor = Theme.of(context).colorScheme.surfaceContainerLow;
      }
    }

    return Container(
      color: bgColor,
      padding: EdgeInsets.only(
        left: 16.0 + (item.indent * 24.0),
        right: 16.0,
        top: 8.0,
        bottom: 8.0,
      ),
      child: Row(
        children: [
          if (item.isUnityPackage)
            const Padding(
              padding: EdgeInsets.only(right: 8.0),
              child: Icon(Icons.inventory_2, size: 16),
            ),
          if (item.indent > 0)
            const Padding(
              padding: EdgeInsets.only(right: 8.0),
              child: Icon(Icons.image, size: 16),
            ),
          Expanded(child: Text(e.displayPath)),
          SizedBox(width: 140, child: Text(e.beforeSize)),
          SizedBox(width: 140, child: Text(e.afterSize)),
          SizedBox(width: 140, child: Text(e.reducedSize)),
          SizedBox(width: 100, child: Text(e.reducedPercent)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _init();
  }

  void _init() async {
    await windowManager.setPreventClose(true);
  }

  @override
  void onWindowClose() async {
    _queue.dispose();
    _pngCompressor.killAll();
    await _unityPackageService.cleanupAll();
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragDone: _addEntries,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: Text(_title()),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: OutlinedButton.icon(
                onPressed: _addFilesFromPicker,
                icon: const Icon(Icons.file_open),
                label: Text(t.add_files),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: OutlinedButton.icon(
                onPressed: _addFolderFromPicker,
                icon: const Icon(Icons.folder_open),
                label: Text(t.add_folder),
              ),
            ),
            if (!_isStarted)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilledButton(
                  onPressed: _startProcessing,
                  child: Text(t.start),
                ),
              ),
            if (_isStarted)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: OutlinedButton(
                  onPressed: _stopProcessing,
                  child: Text(t.stop),
                ),
              ),
          ],
        ),
        body: Column(children: [
          Row(
            children: [
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: TextFormField(
                    decoration: InputDecoration(
                      labelText: t.concurrency,
                    ),
                    controller:
                        TextEditingController(text: _queue.parallel.toString()),
                    onChanged: (v) => setState(() {
                          _queue.parallel = int.parse(v);
                        })),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 140,
                child: CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsetsDirectional.all(0),
                    title: Transform.translate(
                        offset: const Offset(-10, 0), child: Text(t.m)),
                    value: _m,
                    onChanged: (v) => setState(() {
                          _m = v!;
                        })),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 310,
                child: CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsetsDirectional.all(0),
                    title: Transform.translate(
                        offset: const Offset(-10, 0),
                        child: Text(t.lossy_transparent)),
                    value: _lossyTransparent,
                    onChanged: (v) => setState(() {
                          _lossyTransparent = v!;
                        })),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 220,
                child: CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsetsDirectional.all(0),
                    title: Transform.translate(
                        offset: const Offset(-10, 0),
                        child: Text(t.lossy_8bit)),
                    value: _lossy8bit,
                    onChanged: (v) => setState(() {
                          _lossy8bit = v!;
                        })),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 130,
                child: CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsetsDirectional.all(0),
                    title: Transform.translate(
                        offset: const Offset(-10, 0),
                        child: Text(t.preserve_exif)),
                    value: _preserveExif,
                    onChanged: (v) => setState(() {
                          _preserveExif = v!;
                        })),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 210,
                child: CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsetsDirectional.all(0),
                    title: Transform.translate(
                        offset: const Offset(-10, 0),
                        child: Text(t.preserve_text_metadata)),
                    value: _preserveTextMetadata,
                    onChanged: (v) => setState(() {
                          _preserveTextMetadata = v!;
                        })),
              ),
            ],
          ),
          _entries.isEmpty
              ? Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      Text(
                        t.drop_here,
                        style: Theme.of(context).textTheme.headlineMedium,
                      )
                    ]))
              : Expanded(
                  child: Column(
                    children: [
                      Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                                child: Text(t.file,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold))),
                            SizedBox(
                                width: 140,
                                child: Text(t.before,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold))),
                            SizedBox(
                                width: 140,
                                child: Text(t.after,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold))),
                            SizedBox(
                                width: 140,
                                child: Text(t.reduced,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold))),
                            SizedBox(
                                width: 100,
                                child: Text(t.reduced_percent,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold))),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _buildDisplayList().length,
                          itemBuilder: (context, index) {
                            final item = _buildDisplayList()[index];
                            return _buildEntryRow(item);
                          },
                        ),
                      ),
                    ],
                  ),
                )
        ]),
      ),
    );
  }
}

/// Display item for the list view with indent level
class _DisplayItem {
  final EntryInfo entry;
  final int indent;
  final bool isUnityPackage;

  _DisplayItem({
    required this.entry,
    required this.indent,
    this.isUnityPackage = false,
  });
}
