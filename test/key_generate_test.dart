import 'package:dslink/src/crypto/pk.dart';
import 'dart:io';

void main() {
  String rslt;

  if (Platform.isWindows) {
    rslt = Process.runSync('getmac', []).stdout.toString();
  } else {
    rslt = Process.runSync('ifconfig', []).stdout.toString();
  }

  // randomize the PRNG with the system mac
  DSRandom.instance.randomize(rslt);

  var t1 = (new DateTime.now()).millisecondsSinceEpoch;
  // generate private key
  PrivateKey key = new PrivateKey.generate();
  var t2 = (new DateTime.now()).millisecondsSinceEpoch;

  print('takes ${t2-t1} ms to generate key');
  print('dsaId: ${key.publicKey.getDsId('my-dsa-test-')}');
  print('saved key:\n${key.saveToString()}');
  print('public key:\n${key.publicKey.qBase64}');
  //test token encrypt, decrypt
}
