import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webdriver/io.dart';

import 'database.dart';
import 'notifications.dart';

Function consolePrint = print;
class GiveawayClient {

  static const bool VERBOSE = true;

  String _host;
  String _username;
  String _password;
  String _cookies;
  String _consoleUser;
  bool processingGiveaways = false;
  WebDriver _driver;
  int totalPages = -1;
  DatabaseManager _db;
  Notifications notifications;

  GiveawayClient(this._host, this._username, this._password, this._cookies, this._db);

  Future<void> start() async {
    processingGiveaways = true;
    print('Starting giveaways for $_username', true);
    _consoleUser =_username.split('@')[0];
    try {
      _driver = await createDriver(uri: Uri.parse('http://$_host:42069/selenium/'), spec: WebDriverSpec.JsonWire, desired: {'chromeOptions': {
        'args': ['--headless', '--no-sandbox', '--disable-dev-shm-usage']
      }});

      if (this._cookies != null) {
        await _driver.get('https://amazon.com/');

        var cookies = jsonDecode(this._cookies);
        cookies.forEach((cookie) =>
            _driver.cookies.add(Cookie.fromJson(cookie)));
      } else {
        await _driver.get('https://www.amazon.com/ap/signin?_encoding=UTF8&ignoreAuthState=1&openid.assoc_handle=usflex&openid.claimed_id=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&openid.identity=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&openid.mode=checkid_setup&openid.ns=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0&openid.ns.pape=http%3A%2F%2Fspecs.openid.net%2Fextensions%2Fpape%2F1.0&openid.pape.max_auth_age=0&openid.return_to=https%3A%2F%2Fwww.amazon.com%2F%3Fref_%3Dnav_signin&switch_account=');

        var email = await getElement(By.cssSelector('input[type=email]'));
        await email.sendKeys(_username);

        var pass = await getElement(By.cssSelector('input[type=password]'));
        await pass.sendKeys(_password);

        await (await getElement(By.id('signInSubmit'))).click();
      }

      sleep(Duration(seconds: 1));

      await _driver.get('https://www.amazon.com/ga/giveaways/?pageId=1');

      totalPages = int.parse(await (await getElement(By.cssSelector('.ga-pagination > .a-pagination li:nth-last-child(2)'))).text);
      print('Found $totalPages pages');

      for (int page = 1; page < totalPages + 1; page++) {
        await _driver.get('https://www.amazon.com/ga/giveaways/?pageId=$page');
        print('Going to page $page');

        await getElement(By.className('listing-info-container'), duration: 5000);
        var pageLinks = await _driver.findElements(By.cssSelector('.item-link[href^="/ga/p/"]')).map((element) => element.attributes['href']).toList();
        for (var attr in pageLinks) {
          try {
            _attempts = 0;
            _href = await attr;
            await processGiveaway();
          } catch (e) {
            print(e, true);
          }
        }
      }
    } catch (e) {
      print(e, true);
      processingGiveaways = false;
    }
  }

  int _attempts;
  String _href;
  String _id;

  Future<void> processGiveaway() async {
    print('========================= [Processing $_id] =========================');
    _id = _href.substring(6, 22);
    if (await _db.hasCompleted(_username, _id)) {
      print('Skipping $_id');
      return;
    }

    await _driver.get('https://www.amazon.com$_href');

    // Wait for the continue button to  load
    var title = await (await getElement(By.cssSelector('.prize-title'))).text;
    if (title.contains('you didn\'t win')) {
      print('Already didnt win, adding it to database $_id');
      _db.addCompletedGiveaway(_username, _id);
      return;
    }

    if (await shouldReloadDueToError()) return;

    // Try to play YouTube video
    WebElement youTubeVideo = await getElement(By.cssSelector('.youtube-video'), duration: 500, checkInterval: 50);
    if (youTubeVideo != null) {
      print('[VIDEO] YouTube!');
      await processVideo(youTubeVideo, '.youtube-continue-button:not(.a-button-disabled)');
      return;
    }

    var amazonVideo = await getElement(By.cssSelector('.amazon-video'), duration: 500, checkInterval: 50);
    if (amazonVideo != null) {
      print('[VIDEO] Amazon!');
      await processVideo(amazonVideo, '.amazon-video-continue-button:not(.a-button-disabled)');
      return;
    }
    var box = await getElement(By.className('box-click-area'), duration: 500, checkInterval: 50);
    if (box != null) {
      await box.click();
      if (await shouldReloadDueToError()) return;
      print('[CLICK] No entry requirement!');
      processTitle(await waitForTitleChange());
      _db.addCompletedGiveaway(_username, _id);
      return;
    }

    var followAmazonPerson = await getElement(By.className('follow-author-continue-button'), duration: 500, checkInterval: 50);
    if (followAmazonPerson != null) {
      print('[CLICK] Follow author!');
      await followAmazonPerson.click();
      sleep(Duration(milliseconds: 500));
      await followAmazonPerson.click();
      if (await shouldReloadDueToError()) return;
      processTitle(await waitForTitleChange());
      _db.addCompletedGiveaway(_username, _id);
      return;
    }
  }

  // Returns if the processGiveaway should be returned
  Future<bool> shouldReloadDueToError() async {
    bool result = false;
    await Future.delayed(Duration(seconds: 1), () async {
      var extraLarge = await _driver.findElements(
          By.className('a-size-extra-large'));
      if (await extraLarge.length > 0 &&
          (await (await extraLarge.first).text).contains('Giveaway ended') ||
          await (await _driver.findElements(By.className('a-alert-content'))).length > 0 ||
          await (await _driver.findElements(By.className('participation-issue'))).length > 0 ||
          await (await _driver.findElements(By.cssSelector('a[href*=\'mobilephone\']'))).length > 0) {
        if (_attempts > 5) {
          print('Already gone through 5 attempts, moving on...', true);
        } else {
          print('Reloading due to error!');
          _attempts++;
          await processGiveaway();
        }
        result = true;
      }
    });
    return result;
  }

  Future<void> processVideo(WebElement video, String buttonSelector) async {
    await video.click();
    sleep(Duration(milliseconds: 500));
    await video.click();
    sleep(Duration(milliseconds: 500));
    await video.click();
    var continueButton = await getElement(By.cssSelector(buttonSelector), duration: 16000, checkInterval: 1000);
    if (continueButton == null) return;

    await continueButton.click();
    await continueButton.click();

    if (await shouldReloadDueToError()) return;

    processTitle(await waitForTitleChange());

    _db.addCompletedGiveaway(_username, _id);
  }

  Future<String> waitForTitleChange() async {
    var titleElement = await _driver.findElement(By.cssSelector('div.a-section.a-spacing-medium.a-text-left > span'));
    var original = await titleElement.text;
    int duration = 8000;
    while ((await titleElement.text) == original) {
      sleep(Duration(milliseconds: 250));
      duration -= 250;
      if (duration <= 0) return 'didn\'t win';
    }
    return await titleElement.text;
  }

  // Returns if successful
  void processTitle(String title) {
    if (title.contains('didn\'t win')) {
      print('Didn\'t win', true);
    } else if (title.contains('you won!')) {
      print('YOU WON!!!!!!!!!!!    $_href', true);
      File('winners.txt').writeAsStringSync('[${DateTime.now().toIso8601String()}] $_username:$_password > $_href', mode: FileMode.append);
      notifications.sendNotification('You won!', 'The account $_username won a giveaway. This has been logged.');
      sleep(Duration(days: 3));
      exit(0);
    }
  }

  Future<WebElement> getElement(By by, {int duration = 5000, int checkInterval = 100}) async {
    var element;
    do {
      try {
        element = await _driver.findElement(by);
        if (element != null) return element;
      } catch (ignored) {}
      sleep(Duration(milliseconds: checkInterval));
      duration -= checkInterval;
    } while (element == null && duration > 0);
    return element;
  }

  void print(Object object, [important = false]) {
    if (VERBOSE || important) consolePrint("[$_consoleUser] $object");
  }
}
