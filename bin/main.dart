import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mysql1/mysql1.dart';
import 'package:webdriver/io.dart';
import 'package:convert/convert.dart';
import 'package:args/args.dart';
import 'package:yaml/yaml.dart';

import 'database.dart';
import 'giveaway.dart';

DatabaseManager _databaseManager;
List<GiveawayClient> _clients = [];

main(List<String> args) async {
  var parser = ArgParser()
    ..addOption('clients', abbr: 'c', help: 'The amount of clients to run, 0 being all', defaultsTo: '0')
    ..addOption('config', abbr: 'f', help: 'The config file relative to the current path', defaultsTo: 'config.json')
    ..addOption('username', abbr: 'u', help: 'The username of the single account to use.')
    ..addOption('password', abbr: 'p', help: 'The password of the single account to use.');

  var result = parser.parse(args);

  var json = jsonDecode(File(result['config']).readAsStringSync());
  var accounts = Map();
  if (result.wasParsed('username')) {
    if (!result.wasParsed('password')) {
      print('Password must be set when username is also set!');
      return;
    }

    accounts[result['username']] = result['password'];
  } else {
    List<dynamic> configAccounts = json['accounts'];
    int taking = int.parse(result['clients']);
    configAccounts.take(taking == 0 ? configAccounts.length : taking).forEach((account) => accounts[account['username']] = account['password']);
  }

  print('Accounts are:');
  accounts.forEach((user, pass) {
    print('\t$user:$pass');
  });

  Map<String, dynamic> db = json['database'];
  _databaseManager = DatabaseManager();
  _databaseManager.initDatabase(db['host'], db['port'], db['username'], db['password'], db['database']);

  accounts.forEach((user, pass) => _clients.add(GiveawayClient(user, pass, _databaseManager)..start()));

  Timer.periodic(Duration(seconds: 3), (_t) {
    if (_clients.where((client) => client.processingGiveaways).isEmpty) {
      print('All clients have stopped!');
      _t.cancel();
      _databaseManager.conn.close();
      exit(0);
    }
  });
}
