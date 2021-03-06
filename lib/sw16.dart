import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class SW16Device {
  final String ip;
  final String raw;
  String name;
  String version;
  String date;
  String id;

  SW16Device(this.ip, this.raw) {
    var slice = raw.replaceAll(')', '').split('(');
    name = slice[0];
    version = slice[1];
    date = slice[2];
    id = slice[3];
  }

  @override
  String toString() => "$ip: $raw";

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'raw': raw,
        'name': name,
        'version': version,
        'date': date,
        'id': id,
      };
}

class SW16Controller {
  final SW16Device device;
  List<bool> status;
  int _port = 8080;
  bool _connected = false;
  Socket _socket;
  final StreamController<List<bool>> _stream = StreamController();
  List<int> _data = [
    0xaa,
    0X0f,
    0,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    0xbb
  ];

  static const ON = 1;
  static const OFF = 2;

  SW16Controller(this.device) {
    _connect();
  }

  _connect() async {
    if (_connected) {
      return;
    }
    const timeout = Duration(seconds: 2);
    _socket = await Socket.connect(device.ip, _port, timeout: timeout);
    _socket.listen(_onData, onError: (error) {
      _connected = false;
      _connect();
    }, onDone: () {
      _stream.close();
      _socket.destroy();
      _connected = false;
    });
    _connected = true;
  }

  _onData(Uint8List data) {
    if (data[1] == 12) {
      status = data.sublist(2, 18).map((i) => i == 1).toList();
      if (!_stream.isClosed) {
        _stream.sink.add(status);
      }
    }
  }

  _send() {
    _socket.add(_data);
  }

  turn(int index, int state) {
    _data[2] = index;
    _data[3] = state;
    _send();
  }

  turnOn(int index) {
    turn(index, ON);
  }

  turnOff(int index) {
    turn(index, OFF);
  }

  Stream<List<bool>> get onStatusChanged {
    return _stream.stream;
  }
}

class SW16Status {
  final int _index;
  final List<bool> _status;
  SW16Status(this._index, this._status);
  Map<String, dynamic> toJson() => {'index': _index, 'status': _status};
}

class SW16 {
  RawDatagramSocket _udp;
  final StreamController<SW16Device> _onFind = StreamController();
  final StreamController<SW16Status> _onStatusChanged = StreamController();
  final _devices = List<SW16Controller>();

  SW16() {
    RawDatagramSocket.bind(InternetAddress.anyIPv4, 23333).then((udp) {
      _udp = udp;
      udp.broadcastEnabled = true;
      udp.listen((_) {
        var response = udp.receive();
        if (response != null) {
          var address = response.address.address;
          var data = utf8.decode(response.data);
          if (_devices.indexWhere((item) => item.device.raw == data) == -1) {
            var device = SW16Device(address, data);
            var index = _devices.length;
            var controller = SW16Controller(device);
            controller.onStatusChanged.listen((status) {
              _onStatusChanged.sink.add(SW16Status(index, status));
            });
            _devices.add(controller);
            _onFind.sink.add(device);
          }
        }
      }, onDone: () {
        _onFind.close();
      });
    });
  }

  clearDevices() {
    _devices.clear();
  }

  findDevices() {
    _udp.send('HLK'.codeUnits, InternetAddress('255.255.255.255'), 988);
  }

  turnOn(int i, int switchIndex) {
    _devices[i].turnOn(switchIndex);
  }

  turnOff(int i, int switchIndex) {
    _devices[i].turnOff(switchIndex);
  }

  Stream<SW16Device> get onFind => _onFind.stream;

  Stream<SW16Status> get onStatusChanged => _onStatusChanged.stream;

  List<SW16Device> get devices => _devices.map((item) => item.device).toList();
}
