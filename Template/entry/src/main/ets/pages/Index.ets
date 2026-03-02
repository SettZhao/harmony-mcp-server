/**
 * USB Serial Demo Page
 * Demonstrates usb-serial-for-android HarmonyOS port
 *
 * Features:
 * - Enumerate connected USB serial devices
 * - Request USB permission
 * - Connect and set serial parameters (9600, 8N1)
 * - Send text data
 * - Display received data
 */
import { usbManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import {
  UsbSerialProber,
  IUsbSerialDriver,
  IUsbSerialPort,
  DATABITS_8,
  PARITY_NONE,
  STOPBITS_1
} from 'library';

const TAG = 'UsbSerialDemo';
const DOMAIN = 0x0000;

@Entry
@Component
struct Index {
  @State message: string = 'USB Serial Demo';
  @State deviceInfo: string = 'No devices found';
  @State receivedData: string = '';
  @State sendText: string = 'Hello USB!';
  @State isConnected: boolean = false;

  private prober: UsbSerialProber = UsbSerialProber.getDefaultProber();
  private drivers: IUsbSerialDriver[] = [];
  private currentPort: IUsbSerialPort | null = null;
  private currentPipe: usbManager.USBDevicePipe | null = null;

  aboutToAppear(): void {
    this.scanDevices();
  }

  scanDevices(): void {
    this.drivers = this.prober.findAllDrivers();
    if (this.drivers.length === 0) {
      this.deviceInfo = 'No USB serial devices found.\nPlease connect a device (FTDI/CP21xx/CH34x/CDC/Prolific).';
    } else {
      let info = 'Found ' + this.drivers.length + ' device(s):\n';
      for (let i = 0; i < this.drivers.length; i++) {
        const dev = this.drivers[i].getDevice();
        info += (i + 1) + '. VID=0x' + dev.vendorId.toString(16).toUpperCase() +
          ' PID=0x' + dev.productId.toString(16).toUpperCase() +
          ' [' + dev.name + ']\n';
      }
      this.deviceInfo = info;
    }
  }

  async connectToFirstDevice(): Promise<void> {
    if (this.drivers.length === 0) {
      this.message = 'No device to connect';
      return;
    }
    const driver = this.drivers[0];
    const device = driver.getDevice();
    // Request USB permission
    const hasRight = usbManager.hasRight(device.name);
    if (!hasRight) {
      try {
        const granted = await usbManager.requestRight(device.name);
        if (!granted) {
          this.message = 'USB permission denied';
          return;
        }
      } catch (e) {
        this.message = 'Permission request failed: ' + (e as Error).message;
        return;
      }
    }
    try {
      const pipe = usbManager.connectDevice(device);
      this.currentPipe = pipe;
      const port = driver.getPorts()[0];
      await port.open(pipe);
      await port.setParameters(9600, DATABITS_8, STOPBITS_1, PARITY_NONE);
      this.currentPort = port;
      this.isConnected = true;
      this.message = 'Connected! 9600,8N1';
      hilog.info(DOMAIN, TAG, '%{public}s', 'Connected to USB serial device');
    } catch (e) {
      this.message = 'Connect failed: ' + (e as Error).message;
      hilog.error(DOMAIN, TAG, '%{public}s', 'Connect error: ' + (e as Error).message);
    }
  }

  async disconnectDevice(): Promise<void> {
    if (this.currentPort !== null) {
      try {
        await this.currentPort.close();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, '%{public}s', 'Close error: ' + (e as Error).message);
      }
      this.currentPort = null;
    }
    if (this.currentPipe !== null) {
      usbManager.closePipe(this.currentPipe);
      this.currentPipe = null;
    }
    this.isConnected = false;
    this.message = 'Disconnected';
  }

  async sendData(): Promise<void> {
    if (this.currentPort === null) {
      this.message = 'Not connected';
      return;
    }
    try {
      const encoder = new util.TextEncoder();
      const data = encoder.encodeInto(this.sendText);
      await this.currentPort.write(data, 2000);
      this.message = 'Sent ' + data.length + ' bytes';
    } catch (e) {
      this.message = 'Send failed: ' + (e as Error).message;
    }
  }

  async readData(): Promise<void> {
    if (this.currentPort === null) {
      this.message = 'Not connected';
      return;
    }
    try {
      const buf = new Uint8Array(256);
      const numRead = await this.currentPort.read(buf, 500);
      if (numRead > 0) {
        const decoder = new util.TextDecoder();
        const text = decoder.decode(buf.subarray(0, numRead));
        this.receivedData += text;
        if (this.receivedData.length > 500) {
          this.receivedData = this.receivedData.substring(this.receivedData.length - 500);
        }
        this.message = 'Read ' + numRead + ' bytes';
      } else {
        this.message = 'No data received';
      }
    } catch (e) {
      this.message = 'Read failed: ' + (e as Error).message;
    }
  }

  build() {
    Column({ space: 12 }) {
      Text('USB Serial Demo')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 20 })

      Text(this.message)
        .fontSize(14)
        .fontColor(this.isConnected ? Color.Green : Color.Orange)
        .textAlign(TextAlign.Center)
        .width('90%')

      Divider()

      Text('Connected Devices:')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .width('90%')

      Text(this.deviceInfo)
        .fontSize(12)
        .fontColor(Color.Gray)
        .width('90%')
        .backgroundColor('#F5F5F5')
        .padding(8)
        .borderRadius(4)

      Row({ space: 10 }) {
        Button('Scan')
          .onClick(() => this.scanDevices())
          .width(80)

        Button(this.isConnected ? 'Disconnect' : 'Connect')
          .onClick(() => {
            if (this.isConnected) {
              this.disconnectDevice();
            } else {
              this.connectToFirstDevice();
            }
          })
          .width(100)
          .backgroundColor(this.isConnected ? Color.Red : Color.Blue)
      }

      Divider()

      Text('Send Data:')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .width('90%')

      TextInput({ placeholder: 'Enter text to send', text: this.sendText })
        .width('90%')
        .onChange((val: string) => {
          this.sendText = val;
        })

      Row({ space: 10 }) {
        Button('Send')
          .onClick(() => this.sendData())
          .enabled(this.isConnected)
          .width(80)

        Button('Read')
          .onClick(() => this.readData())
          .enabled(this.isConnected)
          .width(80)

        Button('Clear')
          .onClick(() => {
            this.receivedData = '';
          })
          .width(80)
      }

      Divider()

      Text('Received Data:')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .width('90%')

      Scroll() {
        Text(this.receivedData.length > 0 ? this.receivedData : '(no data)')
          .fontSize(12)
          .fontFamily('monospace')
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .width('90%')
      .height(150)
      .backgroundColor('#F5F5F5')
      .padding(8)
      .borderRadius(4)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
