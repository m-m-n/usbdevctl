import 'dart:io';

int main(List<String> arguments) {
  // 引数なければlsusbの結果を表示する
  if (arguments.length < 1) {
    usage();
    return 1;
  }

  final action = arguments[0];
  if (action == 'help') {
    help();
  } else if (action == 'lsusb') {
    printLsUsb();
  } else if (action == 'bind' || action == 'unbind') {
    if (arguments.length < 2) {
      help();
      return 1;
    }

    final subArgs = arguments.sublist(1);
    if (action == 'bind') {
      bind(subArgs);
    } else if (action == 'unbind') {
      unbind(subArgs);
    }
  }
  return 0;
}

void usage() {
  print('check the help. type the following');
  print('  usbdevctl help');
  print('');
  printLsUsb();
}

void help() {
  print('usage: usbdevctl COMMAND [ARGS1 ...]');
  print('');
  print('suppored command list');
  print(' help: this message');
  print(' lsusb: show results `lsusb`');
  print(' bind: connects the device with the vendorID:productID specified in the arguments');
  print('  usbdevctl bind XXXX:xxxx [YYYY:yyyy]');
  print(' unbind: disconnects the device with the vendorID:productID specified in the arguments');
  print('  usbdevctl unbind XXXX:xxxx [YYYY:yyyy]');
}

void printLsUsb() async {
  print((await Process.run('lsusb', [])).stdout);
}

void bind(List<String> ids) async {
  final busIds = await retrieveUsbBusId(ids);
  if (busIds == null) {
    print('device not found');
    return;
  }

  for (var busId in busIds) {
    bindCommand('bind', busId);
  }
}

void unbind(List<String> ids) async {
  final busIds = await retrieveUsbBusId(ids);
  if (busIds == null) {
    print('device not found');
    return;
  }

  for (var busId in busIds) {
    bindCommand('unbind', busId);
  }
}

void bindCommand(String type, String busId) async {
  // echo "$busId" | sudo tee /sys/bus/usb/drivers/usb/unbind
  final echo = await Process.start('echo', [busId]);
  final sudoTee = await Process.start('sudo', ['tee', '/sys/bus/usb/drivers/usb/${type}']);
  echo.stdout.pipe(sudoTee.stdin);
}

Future<List<String>?> retrieveUsbBusId(List<String> ids) async {
  var result = <String>[];
  for (var id in ids) {
    final vid_pid = id.split(':');
    if (vid_pid.length != 2) {
      print('invalid id string: ${id}');
      continue;
    }
    final vid = vid_pid[0];
    final pid = vid_pid[1];
    final busId = await retrieveUsbBusIdFromVidAndPid(vid, pid);
    if (busId == null) {
      print('perhaps a dvice that is not plugged in: ${id}');
      continue;
    }
    if (result.contains(busId)) {
      continue;
    }
    result.add(busId);
  }

  if (result.length < 1) {
    return null;
  }
  return result;
}

Future<String?> retrieveUsbBusIdFromVidAndPid(String vid, String pid) async {
  final baseDir = '/sys/devices/';

  final vidResult = await Process.run('grep', ['-lrs', vid, baseDir]);
  if (vidResult.stdout == "") {
    return null;
  }

  final exp = new RegExp(r'^.*/usb[0-9]+/([^/]+)/id(Vendor|Product)$');

  // vendorIDにひっかかったBUS ID一覧を作る
  var vidMatchBusId = <String>[];
  for (var vidValue in vidResult.stdout.split('\n')) {
    final match = exp.firstMatch(vidValue);
    if (match == null) {
      continue;
    }
    final vidBusId = match.group(1);
    if (vidBusId == null || vidMatchBusId.contains(vidBusId)) {
      continue;
    }
    vidMatchBusId.add(vidBusId);
  }

  final pidResult = await Process.run('grep', ["-lrs", pid, baseDir]);
  if (pidResult.stdout == "") {
    return null;
  }

  // productIDでひっかかったBUS IDがvendorIDでひっかかったBUS IDにもあれば指定したvendorID:productIDのデバイスが接続されているBUS IDなので返す
  // 同じvendorID:productIDのデバイスを複数繋ぐ可能性はあるが現状そのような状況にならないので考えないでおく
  for (var pidValue in pidResult.stdout.split('\n')) {
    if (!exp.hasMatch(pidValue)) {
      continue;
    }
    final match =  exp.firstMatch(pidValue);
    if (match == null) {
      continue;
    }
    final pidBusId = match.group(1);
    if (pidBusId == null) {
      continue;
    }
    if (vidMatchBusId.contains(pidBusId)) {
      return pidBusId;
    }
  }

  return null;
}
