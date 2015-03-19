library dslink.client;

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:args/args.dart';

import 'common.dart';
import 'requester.dart';
import 'responder.dart';
import 'utils.dart';
import 'src/crypto/pk.dart';
import 'src/http/websocket_conn.dart';

export 'src/crypto/pk.dart';

part 'src/http/client_link.dart';
part 'src/http/client_http_conn.dart';

class LinkProvider {
  HttpClientLink link;
  SimpleNodeProvider provider;

  File _nodesFile;
  LinkProvider(List<String> args, String prefix, {bool isRequester: false,
      String command: 'dart link.dart', bool isResponder: true, Map functionMap,
      Map defaultNodes, NodeProvider nodeProvider}) {
    ArgParser argp = new ArgParser();
    argp.addOption('broker', abbr: 'b');
    argp.addOption('configs', abbr: 'c', defaultsTo: 'dslink.config');
    //argp.addOption('key', abbr: 'k', defaultsTo: '.dslink.key');
    //argp.addOption('nodes', abbr: 'n', defaultsTo: 'dslink.json');
    argp.addFlag('help');
    ArgResults opts = argp.parse(args);

    String helpStr =
        'usage:\n$command --broker brokerUrl [--config configFile]';

    if (opts['help'] == true) {
      print(helpStr);
      return;
    }
    String brokerUrl = opts['broker'];
    if (brokerUrl == null) {
      print(helpStr);
      return;
    }
    if (!brokerUrl.startsWith('http')) {
      brokerUrl = 'http://$brokerUrl';
    }

    // load configs
    File configFile = new File.fromUri(Uri.parse(opts['configs']));
    Map configs;
    try {
      String configStr = configFile.readAsStringSync();
      configs = JSON.decode(configStr);
    } catch (err) {}
    if (configs == null || configs['key'] == null) {
      print('Invalid configs\n$helpStr');
      return;
    }
    
    File keyFile = new File.fromUri(Uri.parse(configs['key']));
    String key;
    PrivateKey prikey;
    try {
      key = keyFile.readAsStringSync();
      prikey = new PrivateKey.loadFromString(key);
    } catch (err) {}

    if (key == null || key.length != 131) {
      // 43 bytes d, 87 bytes Q, 1 space
      // generate the key
      String macs;
      if (Platform.isWindows) {
        macs = Process.runSync('getmac', []).stdout.toString();
      } else {
        macs = Process.runSync('ifconfig', []).stdout.toString();
      }
      // randomize the PRNG with the system mac
      DSRandom.instance.randomize(macs);
      prikey = new PrivateKey.generate();
      key = prikey.saveToString();
      keyFile.writeAsString(key);
    }

    if (nodeProvider == null) {
      provider = new SimpleNodeProvider();
      if (functionMap != null) {
        registerFunctions(functionMap);
      }
      nodeProvider = provider;
      _nodesFile = new File.fromUri(Uri.parse(configs['nodes']));
      Map loadedNodesData;
      try {
        String nodesStr = _nodesFile.readAsStringSync();
        loadedNodesData = JSON.decode(nodesStr);
      } catch (err) {}
      if (loadedNodesData != null) {
        provider.init(loadedNodesData);
      } else if (defaultNodes != null) {
        provider.init(defaultNodes);
      }
    }

    link = new HttpClientLink(brokerUrl, prefix, prikey,
        isRequester: isRequester,
        isResponder: isResponder,
        nodeProvider: nodeProvider);
  }
  void connect() {
    if (link != null) link.connect();
  }
  void save() {
    if (_nodesFile != null && provider != null) {
      _nodesFile.writeAsString(JSON.encode(provider.save()));
    }
  }
  void registerFunctions(Map map) {
    map.forEach((String key, Function f) {
      provider.registerFunction(key, f);
    });
    provider.nodes.forEach((path, node) {
      if (node is SimpleNode){
        node.updateFunction(provider);
      }
    });
  }
}