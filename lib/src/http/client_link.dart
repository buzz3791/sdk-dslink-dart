part of dslink.client;

/// a client link for both http and ws
class HttpClientLink implements ClientLink {
  Completer<Requester> _onRequesterReadyCompleter = new Completer<Requester>();
  Future<Requester> get onRequesterReady => _onRequesterReadyCompleter.future;

  final String dsId;

  final Requester requester;
  final Responder responder;
  final PrivateKey privateKey;

  ECDH _nonce;
  ECDH get nonce => _nonce;

  WebSocketConnection _wsConnection;
  HttpClientConnection _httpConnection;

  static const Map<String, int> saltNameMap = const {'salt': 0, 'saltS': 1, 'saltL': 2,};

  /// 2 salts, salt and saltS
  final List<String> salts = new List<String>(3);

  updateSalt(String salt, [int saltId = 0]) {
    salts[saltId] = salt;
  }

  String _wsUpdateUri;
  String _httpUpdateUri;
  String _conn;
  bool enableHttp;
  HttpClientLink(this._conn, String dsIdPrefix, PrivateKey privateKey,
      {NodeProvider nodeProvider, bool isRequester: true,
      bool isResponder: true, this.enableHttp:false})
      : privateKey = privateKey,
        dsId = '$dsIdPrefix${privateKey.publicKey.qHash64}',
        requester = isRequester ? new Requester() : null,
        responder = (isResponder && nodeProvider != null)
            ? new Responder(nodeProvider)
            : null {}

  int _connDelay = 1;
  connect() async {
    if (_closed) return;

    DsTimer.timerCancel(initWebsocket);

    HttpClient client = new HttpClient();
    Uri connUri = Uri.parse('$_conn?dsId=$dsId');
    logger.info('connecting: $connUri');
    try {
      HttpClientRequest request = await client.postUrl(connUri);
      Map requestJson = {
        'publicKey': privateKey.publicKey.qBase64,
        'isRequester': requester != null,
        'isResponder': responder != null,
        'version': DSA_VERSION
      };

      logger.fine("DS ID: ${dsId}");

      request.add(UTF8.encode(DsJson.encode(requestJson)));
      HttpClientResponse response = await request.close();
      List<int> merged = await response.fold([], foldList);
      String rslt = UTF8.decode(merged);
      Map serverConfig = DsJson.decode(rslt);
      saltNameMap.forEach((name, idx) {
        //read salts
        salts[idx] = serverConfig[name];
      });
      String tempKey = serverConfig['tempKey'];
      _nonce = privateKey.decodeECDH(tempKey);

      if (serverConfig['wsUri'] is String) {
        _wsUpdateUri = '${connUri.resolve(serverConfig['wsUri'])}?dsId=$dsId'
            .replaceFirst('http', 'ws');
      }

      if (serverConfig['httpUri'] is String) {
        // TODO implement http
        _httpUpdateUri = '${connUri.resolve(serverConfig['httpUri'])}?dsId=$dsId';
      }

      initWebsocket(false);
      _connDelay = 1;
      _wsDelay = 1;
      //initHttp();

    } catch (err) {
      DsTimer.timerOnceAfter(connect, _connDelay * 1000);
      if (_connDelay < 60)_connDelay++;
    }
  }

  int _wsDelay = 1;

  initWebsocket([bool reconnect = true]) async {
    if (_closed) return;

    if(reconnect && _httpConnection == null) {
      initHttp();
    }
    try {
      var socket = await WebSocket
          .connect('$_wsUpdateUri&auth=${_nonce.hashSalt(salts[0])}');
      _wsConnection = new WebSocketConnection(socket, clientLink: this, enableTimeout:true);

      if (responder != null) {
        responder.connection = _wsConnection.responderChannel;
      }

      if (requester != null) {
        _wsConnection.onRequesterReady.then((channel) {
          requester.connection = channel;
          if (!_onRequesterReadyCompleter.isCompleted) {
            _onRequesterReadyCompleter.complete(requester);
          }
        });
      }
      _wsConnection.onDisconnected.then((connection) {
        initWebsocket();
        print('websocket disconnected');
      });
    } catch (error) {
      logger.fine(error);
      if (error is WebSocketException && error.message.contains('was not upgraded to websocket')){
        DsTimer.timerOnceAfter(connect, _connDelay * 1000);
      } else if (reconnect) {
         DsTimer.timerOnceAfter(initWebsocket, _wsDelay*1000);
         if (_wsDelay < 60)_wsDelay++;
      } else {
        initHttp();
         _wsDelay = 5;
         DsTimer.timerOnceAfter(initWebsocket, 5000);
      }
    }
  }

  initHttp() async {
    if (!enableHttp) {
      return;
    }

    if (_closed) return;

    _httpConnection =
        new HttpClientConnection(_httpUpdateUri, this, salts[2], salts[1]);

    if (responder != null) {
      responder.connection = _httpConnection.responderChannel;
    }

    if (requester != null) {
      _httpConnection.onRequesterReady.then((channel) {
        requester.connection = channel;
        if (!_onRequesterReadyCompleter.isCompleted) {
          _onRequesterReadyCompleter.complete(requester);
        }
      });
    }

    _httpConnection.onDisconnected.then((bool authFailed){
      if (_closed) return;
      _httpConnection = null;
      if (authFailed) {
        DsTimer.timerOnceAfter(connect, _connDelay * 1000);
      } else {
        // reconnection of websocket should handle this case
      }
    });
  }

  bool _closed = false;
  void close() {
    if (_closed) return;
    _closed = true;
    if (_wsConnection != null) {
      _wsConnection.close();
      _wsConnection = null;
    }
    if (_httpConnection != null) {
      _httpConnection.close();
      _httpConnection = null;
    }
  }
}

PrivateKey getKeyFromFile(String path) {
  var file = new File(path);

  PrivateKey key;
  if (!file.existsSync()) {
    key = new PrivateKey.generate();
    file.createSync(recursive: true);
    file.writeAsStringSync(key.saveToString());
  } else {
    key = new PrivateKey.loadFromString(file.readAsStringSync());
  }

  return key;
}
