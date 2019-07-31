import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:process_run/process_run.dart';

import 'database.dart';
import 'giveaway.dart';

DatabaseManager _databaseManager;
List<GiveawayClient> _clients = [];

main(List<String> args) async {
  var parser = ArgParser()
    ..addOption('clients', abbr: 'c', help: 'The amount of clients to run, 0 being all', defaultsTo: '0')
    ..addOption('index', abbr: 'i', help: 'The starting index of the accounts in the config', defaultsTo: '0')
    ..addOption('config', abbr: 'f', help: 'The config file relative to the current path', defaultsTo: 'config.json')
    ..addOption('username', abbr: 'u', help: 'The username of the single account to use.')
    ..addOption('password', abbr: 'p', help: 'The password of the single account to use.', defaultsTo: null)
    ..addOption('cookies', abbr: 'q', help: 'The JSON cookies of the single account to use.', defaultsTo: null);

  var result = parser.parse(args);

  var json = jsonDecode(File(result['config']).readAsStringSync());
  if (result.wasParsed('username')) {
    if (!result.wasParsed('password') && !result.wasParsed('cookies')) {
      print('Password or cookies must be set when username is also set!');
      return;
    }
  } else {
    var accounts = Map();
    List<dynamic> configAccounts = json['accounts'];
    int taking = int.parse(result['clients']);
    int starting = int.parse(result['index']);
    configAccounts.skip(starting).take(taking == 0 ? configAccounts.length : taking).forEach((account) => accounts[account['username']] = account);

    var futures = <Future>[];
    for (var user in accounts.keys) {
      var cookies = accounts[user]['cookies'];
      var command = <String>[r'E:\AmazonGiveaway\bin\main.dart', '-f', "E:\\AmazonGiveaway\\${result['config']}", '-u', user, '-q', jsonEncode(cookies)];
      print('Running dart ${command.join(' ')}');
      futures.add(run(r'C:\Program Files\Dart\dart-sdk\bin\dart.exe', command, verbose: true).then((process) {
        print('Done with $user');
      }));
    }

    await Future.wait(futures);
    print('All clients from child processes have completed!');
    return;
  }

  Map<String, dynamic> db = json['database'];
  _databaseManager = DatabaseManager();
  _databaseManager.initDatabase(db['host'], db['port'], db['username'], db['password'], db['database']);

  var user = result['username'];
  var pass = result['password'];
  var cookies = result['cookies'];
  print('Username: $user');
  print('Cookies: $cookies');
  var client = GiveawayClient(json['host'], user, pass, cookies, _databaseManager);
  await client.start();

  print('[$user] Client has stopped!');
  await _databaseManager.conn?.close();
  exit(0);
}
