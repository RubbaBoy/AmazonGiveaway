import 'dart:io';

import 'package:webdriver/io.dart';
import 'package:webdriver/support/forwarder.dart';

import 'database.dart';

class GiveawayClient {

  String _username;
  String _password;
  bool processingGiveaways = false;
  WebDriver _driver;
  int totalPages = -1;
  DatabaseManager _db;

  GiveawayClient(this._username, this._password, this._db);

  Future start() async {
    processingGiveaways = true;
    print('Starting giveaways for $_username');
    try {

      _driver = await createDriver(spec: WebDriverSpec.JsonWire);
      await _driver.get('https://www.amazon.com/ap/signin?_encoding=UTF8&ignoreAuthState=1&openid.assoc_handle=usflex&openid.claimed_id=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&openid.identity=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&openid.mode=checkid_setup&openid.ns=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0&openid.ns.pape=http%3A%2F%2Fspecs.openid.net%2Fextensions%2Fpape%2F1.0&openid.pape.max_auth_age=0&openid.return_to=https%3A%2F%2Fwww.amazon.com%2F%3Fref_%3Dnav_signin&switch_account=');

      var email = await getElement(By.cssSelector('input[type=email]'));
      await email.sendKeys(_username);

      var pass = await getElement(By.cssSelector('input[type=password]'));
      await pass.sendKeys(_password);

      await (await getElement(By.id('signInSubmit'))).click();

      await _driver.get('https://www.amazon.com/ga/giveaways/?pageId=1');

      totalPages = int.parse(await (await getElement(By.cssSelector('.ga-pagination > .a-pagination li:nth-last-child(2)'))).text);
      print('Found $totalPages pages');

      for (int page = 1; page < totalPages + 1; page++) {
        await _driver.get('https://www.amazon.com/ga/giveaways/?pageId=$page');
        print('Going to page $page');

        await getElement(By.className('listing-info-container'), duration: 5000);
        var pageLinks = await _driver.findElements(By.cssSelector('.item-link[href^="/ga/p/"]')).map((element) => element.attributes['href']).toList();
        print(pageLinks);
        for (var attr in pageLinks) {
          try {
            await processGiveaway(await attr);
          } catch (e) {
            print(e);
          }
        }
      }
    } catch (e) {
      print(e);
      processingGiveaways = false;
    }
  }

  Future<void> processGiveaway(String href, {int attempts = 0}) async {
    print('================================================');
    var id = href.substring(6, 22);
    if (await _db.hasCompleted(_username, id)) {
      print('Skipping $id');
      return;
    }

    await _driver.get('https://www.amazon.com$href');

    print('Processing $id');

    // Wait for the continue button to  load
    var title = await (await getElement(By.cssSelector('.prize-title'))).text;
    if (title.contains('you didn\'t win')) {
      print('Already didnt win, adding it to database $id');
      _db.addCompletedGiveaway(_username, id);
      return;
    }

    if (await shouldReloadDueToError()) {
      if (attempts > 3) {
        print('Already gone through 3 attempts, moving on...');
      } else {
        print('Reloading due to error!');
        await processGiveaway(href, attempts: attempts + 1);
      }
      return;
    }

    // Try to play YouTube video
    WebElement youTubeVideo = await getElement(By.cssSelector('.youtube-video'), duration: 2000);
    if (youTubeVideo != null) {
      print('[VIDEO] YouTube!');
      await processVideo(youTubeVideo, href, id, '.youtube-continue-button:not(.a-button-disabled)');
      return;
    }

    var amazonVideo = await getElement(By.cssSelector('.amazon-video'), duration: 2000);
    if (amazonVideo != null) {
      print('[VIDEO] Amazon!');
      await processVideo(amazonVideo, href, id, '.amazon-video-continue-button:not(.a-button-disabled)');
      return;
    }
    var box = await getElement(By.className('box-click-area'));
    if (box != null) {
      await box.click();
      print('[CLICK] No entry requirement!');
      processTitle(await waitForTitleChange(), href);
      _db.addCompletedGiveaway(_username, id);
      return;
    }

    var followAmazonPerson = await getElement(By.className('follow-author-continue-button'));
    if (followAmazonPerson != null) {
      print('[CLICK] Follow author!');
      await followAmazonPerson.click();
      processTitle(await waitForTitleChange(), href);
      _db.addCompletedGiveaway(_username, id);
      return;
    }
  }

  Future<bool> shouldReloadDueToError() async {
    if (await (await _driver.findElements(By.className('a-alert-content'))).length > 0) return true;
    if (await (await _driver.findElements(By.cssSelector('a[href*=\'mobilephone\']'))).length > 0) return true;
    var extraLarge = await _driver.findElements(By.className('a-size-extra-large'));
    if (await extraLarge.length > 0 && (await (await extraLarge.first).text).contains('Giveaway ended')) return true;
    return false;
  }

  Future<void> processVideo(WebElement video, String url, String id, String buttonSelector) async {
    await video.click();
    sleep(Duration(milliseconds: 500));
    await video.click();
    sleep(Duration(milliseconds: 500));
    await video.click();
    var continueButton = await getElement(By.cssSelector(buttonSelector), duration: 16000, checkInterval: 1000);
    if (continueButton == null) return;

    await continueButton.click();
    await continueButton.click();

    var newText = await waitForTitleChange();

    await processTitle(newText, url);

    _db.addCompletedGiveaway(_username, id);
  }

  Future<String> waitForTitleChange() async {
    var titleElement = await _driver.findElement(By.className('prize-title'));
    var original = await titleElement.text;
    while ((await titleElement.text) == original) {
      sleep(Duration(milliseconds: 250));
    }
    return await titleElement.text;
  }

  void processTitle(String title, String url) {
    if (title.contains('didn\'t win')) {
      print('Didn\'t win');
    } else if (title.contains('you won!')) {
      print('YOU WON!!!!!!!!!!!    $url');
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
}
