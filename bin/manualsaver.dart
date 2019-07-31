import 'dart:convert';
import 'dart:io';

import 'package:webdriver/sync_io.dart';


WebDriver _driver;
JsonEncoder encoder = JsonEncoder.withIndent('  ');
var inputConfig;
Future main(List<String> args) async {
  inputConfig = jsonDecode(File('config.json').readAsStringSync());

  _driver = await createDriver(uri: Uri.parse('http://localhost:4444/'), spec: WebDriverSpec.JsonWire, desired: {'chromeOptions': {
    'args': ['--no-sandbox', '--disable-dev-shm-usage']
  }});

  List accounts = inputConfig['accounts'];

  for (var account in accounts) {
    if (account['cookies'] != null) continue;
    await processAccount(accounts, account);
  }
}

Future<void> processAccount(List accounts, Map<String, dynamic> account) async {
  await _driver.get('https://www.amazon.com/ap/signin?_encoding=UTF8&ignoreAuthState=1&openid.assoc_handle=usflex&openid.claimed_id=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&openid.identity=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&openid.mode=checkid_setup&openid.ns=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0&openid.ns.pape=http%3A%2F%2Fspecs.openid.net%2Fextensions%2Fpape%2F1.0&openid.pape.max_auth_age=0&openid.return_to=https%3A%2F%2Fwww.amazon.com%2F%3Fref_%3Dnav_signin&switch_account=');
  print('Done waiting!');

  await (await getElement(By.id('ap_email'))).sendKeys(account['username']);
  var password = await getElement(By.id('ap_password'));
  await password.clear();
  await password.sendKeys(account['username']); // account['password']

  var line = stdin.readLineSync(encoding: Encoding.getByName('utf-8')).toLowerCase();

  if (line == 'c') {
    print('Saving cookies...');
    account['password'] = account['username'];
    account['cookies'] = _driver.cookies.all.map((cookie) => cookie.toJson()).toList();
    inputConfig['accounts'] = accounts;
    File('config.json').writeAsStringSync(encoder.convert(inputConfig));
  }

  sleep(Duration(seconds: 1));

  await _driver.get('https://www.amazon.com/gp/flex/sign-out.html?ie=UTF8&action=sign-out&path=%2Fgp%2Fyourstore%2Fhome&ref_=nav_youraccount_signout&signIn=1&useRedirectOnSuccess=1');

  print('Doing on in 1 second...');
  sleep(Duration(seconds: 1));
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
