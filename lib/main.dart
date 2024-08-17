import 'dart:io';

import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;
import 'package:queue/queue.dart';
import 'package:window_manager/window_manager.dart';
import './i18n/strings.g.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LocaleSettings.useDeviceLocale();
  runApp(TranslationProvider(child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'multi zopflipng',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'multi zopflipng'),
      locale: TranslationProvider.of(context).flutterLocale, // use provider
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class EntryInfo {
  final String path;
  final int before;
  bool processing = false;
  int? after;
  int? get reduced => isProcessed ? before - after! : null;
  double? get reducedRate => isProcessed ? reduced! / before : null;
  bool get isProcessed => after != null;
  String get beforeSize => filesize(before);
  String get afterSize => isProcessed ? filesize(after!) : "";
  String get reducedSize => isProcessed ? "-${filesize(reduced!)}" : "";
  String get reducedPercent =>
      isProcessed ? "-${(reducedRate! * 100).toStringAsFixed(2)}" : "";

  EntryInfo(this.path, this.before);
}

class _MyHomePageState extends State<MyHomePage> with WindowListener {
  final Queue _queue = Queue(parallel: Platform.numberOfProcessors ~/ 2);
  final List<EntryInfo> _entries = [];
  final Set<Process> _processes = {};
  bool _m = true;
  bool _lossyTransparent = false;
  bool _lossy8bit = false;

  void _addEntries(DropDoneDetails details) async {
    var addFiles = List<EntryInfo>.empty(growable: true);
    for (var f in details.files) {
      if (await FileSystemEntity.isDirectory(f.path)) {
        await for (var ff in Directory(f.path).list(recursive: true)) {
          if (await FileSystemEntity.isFile(ff.path) &&
              p.extension(ff.path).toLowerCase() == ".png") {
            addFiles.add(EntryInfo(ff.path, await File(ff.path).length()));
          }
        }
      } else if (p.extension(f.path).toLowerCase() == ".png") {
        addFiles.add(EntryInfo(f.path, await File(f.path).length()));
      }
    }
    setState(() {
      _entries.addAll(addFiles);
    });
    for (var e in addFiles) {
      _queue.add(() async {
        var args = <String>[];
        if (_m) {
          args.add("-m");
        }
        if (_lossyTransparent) {
          args.add("--lossy_transparent");
        }
        if (_lossy8bit) {
          args.add("--lossy_8bit");
        }
        args.add("-y");
        args.add(e.path);
        args.add(e.path);
        setState(() {
          e.processing = true;
        });
        var process = await Process.start("zopflipng.exe", args);
        _processes.add(process);
        if (await process.exitCode != 0) {
          print(process.stderr);
        }
        _processes.remove(process);
        var after = await File(e.path).length();
        setState(() {
          e.processing = false;
          e.after = after;
        });
      });
    }
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
    for (var p in _processes) {
      p.kill(ProcessSignal.sigkill);
    }
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return DropTarget(
      onDragDone: _addEntries,
      child: Scaffold(
        appBar: AppBar(
          // TRY THIS: Try changing the color here to a specific color (to
          // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
          // change color while the other colors stay the same.
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          // Here we take the value from the MyHomePage object that was created by
          // the App.build method, and use it to set our appbar title.
          title: Text(_title()),
        ),
        body: Column(children: [
          Row(
            children: [
              const SizedBox(width: 10),
              SizedBox(
                width: 100,
                child: TextFormField(
                    decoration: InputDecoration(
                      labelText: t.concurrency,
                    ),
                    controller:
                        TextEditingController(text: _queue.parallel.toString()),
                    // initialValue: _queue.parallel.toString(),
                    //keyboardType: TextInputType.number,
                    //inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) => setState(() {
                          _queue.parallel = int.parse(v);
                        })),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 200,
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
              const SizedBox(width: 10),
              SizedBox(
                width: 350,
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
              const SizedBox(width: 10),
              SizedBox(
                width: 350,
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
                  child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SizedBox(
                          width: double.infinity,
                          child: DataTable(
                            columns: [
                              DataColumn(label: Text(t.file)),
                              DataColumn(label: Text(t.before)),
                              DataColumn(label: Text(t.after)),
                              DataColumn(label: Text(t.reduced)),
                              DataColumn(label: Text(t.reduced_percent)),
                            ],
                            rows: _entries
                                .map((f) => DataRow(
                                        color: f.processing
                                            ? WidgetStateProperty.resolveWith(
                                                (states) {
                                                return Colors.yellow;
                                              })
                                            : null,
                                        cells: [
                                          DataCell(Text(f.path)),
                                          DataCell(Text(f.beforeSize)),
                                          DataCell(Text(f.afterSize)),
                                          DataCell(Text(f.reducedSize)),
                                          DataCell(Text(f.reducedPercent)),
                                        ]))
                                .toList(),
                          ))))
        ]),
      ),
    );
  }
}
