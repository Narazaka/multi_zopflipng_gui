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
import './services/zopflipng_options.dart';
import './services/png_compressor.dart';

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
  final List<PngEntryInfo> _entries = [];
  final PngCompressor _pngCompressor = PngCompressor();

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
    var addEntries = <PngEntryInfo>[];
    for (var f in details.files) {
      if (await FileSystemEntity.isDirectory(f.path)) {
        await for (var ff in Directory(f.path).list(recursive: true)) {
          if (await FileSystemEntity.isFile(ff.path)) {
            final ext = p.extension(ff.path).toLowerCase();
            if (ext == ".png") {
              addEntries.add(PngEntryInfo(ff.path, await File(ff.path).length()));
            }
          }
        }
      } else {
        final ext = p.extension(f.path).toLowerCase();
        if (ext == ".png") {
          addEntries.add(PngEntryInfo(f.path, await File(f.path).length()));
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

  void _addFilesFromPicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png'],
      allowMultiple: true,
    );
    if (result == null) return;

    var addEntries = <PngEntryInfo>[];
    for (var file in result.files) {
      if (file.path != null) {
        final ext = p.extension(file.path!).toLowerCase();
        if (ext == ".png") {
          addEntries.add(PngEntryInfo(file.path!, await File(file.path!).length()));
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

    var addEntries = <PngEntryInfo>[];
    await for (var file in Directory(result).list(recursive: true)) {
      if (await FileSystemEntity.isFile(file.path)) {
        final ext = p.extension(file.path).toLowerCase();
        if (ext == ".png") {
          addEntries.add(PngEntryInfo(file.path, await File(file.path).length()));
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

  void _enqueueEntries(List<PngEntryInfo> entries) {
    final currentSession = _sessionId;
    for (var e in entries) {
      _enqueuePngEntry(e, currentSession);
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
      }
    });
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
                          itemCount: _entries.length,
                          itemBuilder: (context, index) {
                            final e = _entries[index];
                            return Container(
                              color: e.processing ? Colors.yellow : null,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 16),
                              child: Row(
                                children: [
                                  Expanded(child: Text(e.path)),
                                  SizedBox(width: 140, child: Text(e.beforeSize)),
                                  SizedBox(width: 140, child: Text(e.afterSize)),
                                  SizedBox(width: 140, child: Text(e.reducedSize)),
                                  SizedBox(width: 100, child: Text(e.reducedPercent)),
                                ],
                              ),
                            );
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
