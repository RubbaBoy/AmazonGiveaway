import 'package:mysql1/mysql1.dart';

class DatabaseManager {

  MySqlConnection conn;

  void initDatabase(String host, int port, String username, String password, String database) async {
    print('Connecting to database $host:$port');

    conn = await MySqlConnection.connect(ConnectionSettings(
        host: host, port: port, user: username, password: password, db: database));

    print('Connected to $host:$port@$username');

    await conn.query("""
      CREATE TABLE IF NOT EXISTS `CompletedGiveaways` (
        username VARCHAR(64),
        giveaway VARCHAR(16)
      );  
      """);
  }

  void addCompletedGiveaway(String username, String giveaway) {
    conn.query('INSERT INTO `CompletedGiveaways` VALUES (\'$username\', \'$giveaway\';');
  }

  Future<bool> hasCompleted(String username, String giveaway) async {
    return Future.value(conn.query('SELECT * FROM `CompletedGiveaways` WHERE username = \'$username\' AND giveaway = \'$giveaway\';').then((re) => re?.isNotEmpty));
  }
}