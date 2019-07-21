class GiveawayClient {

  String username;
  String password;
  bool processingGiveaways = false;

  GiveawayClient(this.username, this.password);

  void start() {
    processingGiveaways = true;
    print('Starting giveaways for $username');
    try {



    } catch (e) {
      print(e);
      processingGiveaways = false;
    }
  }
}