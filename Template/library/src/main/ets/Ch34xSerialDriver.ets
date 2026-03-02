/**
 * WCH CH34x USB Serial Driver (CH340/CH341)
 * Ported from usb-serial-for-android Ch34xSerialDriver to HarmonyOS ArkTS
 */
import { usbManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { IUsbSerialDriver, IUsbSerialPort } from './IUsbSerial';
import { CommonUsbSerialPort } from './CommonUsbSerialPort';
import * as UsbId from './UsbId';

const TAG = 'Ch34xSerialDriver';
const DOMAIN = 0x0000;
const USB_TIMEOUT_MILLIS = 5000;
const DEFAULT_BAUD_RATE = 9600;

// Baud rate table: [baudRate, reg1312, reg0f2c]
const BAUD_TABLE: number[] = [
  2400, 0xd901, 0x0038,
  4800, 0x6402, 0x001f,
  9600, 0xb202, 0x0013,
  19200, 0xd902, 0x000d,
  38400, 0x6403, 0x000a,
  115200, 0xcc03, 0x0008
];

class Ch340SerialPort extends CommonUsbSerialPort {
  private mDriverRef: Ch34xSerialDriver;
  private mDtr: boolean = false;
  private mRts: boolean = false;
  private mReadEndpoint: usbManager.USBEndpoint | null = null;
  private mWriteEndpoint: usbManager.USBEndpoint | null = null;

  constructor(device: usbManager.USBDevice, portNumber: number, driver: Ch34xSerialDriver) {
    super(device, portNumber);
    this.mDriverRef = driver;
  }

  getDriver(): IUsbSerialDriver {
    return this.mDriverRef;
  }

  private async controlOut(request: number, value: number, index: number): Promise<number> {
    const REQTYPE_HOST_TO_DEVICE = 0x41;
    return this.controlTransfer(REQTYPE_HOST_TO_DEVICE, request, value, index, null, 0, USB_TIMEOUT_MILLIS);
  }

  private async controlIn(request: number, value: number, index: number, buffer: Uint8Array): Promise<number> {
    const REQTYPE_VENDOR_IN = 0xC0; // USB_TYPE_VENDOR | USB_DIR_IN
    return this.controlTransfer(REQTYPE_VENDOR_IN, request, value, index, buffer, buffer.length, USB_TIMEOUT_MILLIS);
  }

  private async checkState(msg: string, request: number, value: number, expected: number[]): Promise<void> {
    const buffer = new Uint8Array(expected.length);
    const ret = await this.controlIn(request, value, 0, buffer);
    if (ret < 0) {
      throw new Error('Failed send cmd [' + msg + ']');
    }
    if (ret !== expected.length) {
      throw new Error('Expected ' + expected.length + ' bytes, but got ' + ret + ' [' + msg + ']');
    }
    for (let i = 0; i < expected.length; i++) {
      if (expected[i] === -1) {
        continue;
      }
      const current = buffer[i] & 0xFF;
      if (expected[i] !== current) {
        throw new Error('Expected 0x' + expected[i].toString(16) + ' but got 0x' + current.toString(16) + ' [' + msg + ']');
      }
    }
  }

  private async writeHandshakeByte(): Promise<void> {
    const val = ~((this.mDtr ? 1 << 5 : 0) | (this.mRts ? 1 << 6 : 0)) & 0xFF;
    if (await this.controlOut(0xa4, val, 0) < 0) {
      throw new Error('Failed to set handshake byte');
    }
  }

  private async setBaudRate(baudRate: number): Promise<void> {
    for (let i = 0; i < BAUD_TABLE.length / 3; i++) {
      if (BAUD_TABLE[i * 3] === baudRate) {
        let ret = await this.controlOut(0x9a, 0x1312, BAUD_TABLE[i * 3 + 1]);
        if (ret < 0) { throw new Error('Error setting baud rate. #1'); }
        ret = await this.controlOut(0x9a, 0x0f2c, BAUD_TABLE[i * 3 + 2]);
        if (ret < 0) { throw new Error('Error setting baud rate. #2'); }
        return;
      }
    }
    throw new Error('Baud rate ' + baudRate + ' currently not supported');
  }

  private async initialize(): Promise<void> {
    await this.checkState('init #1', 0x5f, 0, [-1, 0x00]);

    if (await this.controlOut(0xa1, 0, 0) < 0) {
      throw new Error('init failed! #2');
    }

    await this.setBaudRate(DEFAULT_BAUD_RATE);

    await this.checkState('init #4', 0x95, 0x2518, [-1, 0x00]);

    if (await this.controlOut(0x9a, 0x2518, 0x0050) < 0) {
      throw new Error('init failed! #5');
    }

    await this.checkState('init #6', 0x95, 0x0706, [0xFF, 0xEE]);

    if (await this.controlOut(0xa1, 0x501f, 0xd90a) < 0) {
      throw new Error('init failed! #7');
    }

    await this.setBaudRate(DEFAULT_BAUD_RATE);
    await this.writeHandshakeByte();
    await this.checkState('init #10', 0x95, 0x0706, [-1, 0xEE]);
  }

  async open(pipe: usbManager.USBDevicePipe): Promise<void> {
    if (this.mPipe !== null) {
      throw new Error('Already opened.');
    }
    this.mPipe = pipe;
    let opened = false;
    try {
      const configs = this.mDevice.configs;
      if (!configs || configs.length === 0) {
        throw new Error('No USB configurations found');
      }
      const interfaces = configs[0].interfaces;
      for (let i = 0; i < interfaces.length; i++) {
        const res = usbManager.claimInterface(this.mPipe, interfaces[i], true);
        hilog.info(DOMAIN, TAG, 'claimInterface %{public}d result=%{public}d', i, res);
      }

      const dataIface = interfaces[interfaces.length - 1];
      for (let i = 0; i < dataIface.endpoints.length; i++) {
        const ep = dataIface.endpoints[i];
        if (ep.type === 2) {
          if (ep.direction === 0x80) {
            this.mReadEndpoint = ep;
          } else {
            this.mWriteEndpoint = ep;
          }
        }
      }

      await this.initialize();
      await this.setBaudRate(DEFAULT_BAUD_RATE);
      opened = true;
    } finally {
      if (!opened) {
        await this.close();
      }
    }
  }

  async close(): Promise<void> {
    if (this.mPipe === null) {
      throw new Error('Already closed');
    }
    try {
      usbManager.closePipe(this.mPipe);
    } finally {
      this.mPipe = null;
    }
  }

  async read(dest: Uint8Array, timeoutMillis: number): Promise<number> {
    if (!this.mReadEndpoint) {
      throw new Error('Read endpoint not set');
    }
    const readAmt = Math.min(dest.length, this.mReadBuffer.length);
    const readBuf = this.mReadBuffer.subarray(0, readAmt);
    const numBytesRead = await this.bulkTransfer(this.mReadEndpoint, readBuf, timeoutMillis);
    if (numBytesRead < 0) {
      return 0;
    }
    dest.set(this.mReadBuffer.subarray(0, numBytesRead), 0);
    return numBytesRead;
  }

  async write(src: Uint8Array, timeoutMillis: number): Promise<number> {
    if (!this.mWriteEndpoint) {
      throw new Error('Write endpoint not set');
    }
    let offset = 0;
    while (offset < src.length) {
      const writeLength = Math.min(src.length - offset, this.mWriteBuffer.length);
      const writeBuffer = offset === 0 ? src.subarray(0, writeLength) : (() => {
        this.mWriteBuffer.set(src.subarray(offset, offset + writeLength), 0);
        return this.mWriteBuffer.subarray(0, writeLength);
      })();
      const amtWritten = await this.bulkTransfer(this.mWriteEndpoint, writeBuffer, timeoutMillis);
      if (amtWritten <= 0) {
        throw new Error('Error writing ' + writeLength + ' bytes at offset ' + offset);
      }
      offset += amtWritten;
    }
    return offset;
  }

  async setParameters(baudRate: number, dataBits: number, stopBits: number, parity: number): Promise<void> {
    await this.setBaudRate(baudRate);
    // Data bits, stop bits, parity not fully implemented in original driver for CH34x
  }

  getCD(): boolean { return false; }
  getCTS(): boolean { return false; }
  getDSR(): boolean { return false; }
  getDTR(): boolean { return this.mDtr; }

  async setDTR(value: boolean): Promise<void> {
    this.mDtr = value;
    await this.writeHandshakeByte();
  }

  getRI(): boolean { return false; }
  getRTS(): boolean { return this.mRts; }

  async setRTS(value: boolean): Promise<void> {
    this.mRts = value;
    await this.writeHandshakeByte();
  }

  async purgeHwBuffers(purgeReadBuffers: boolean, purgeWriteBuffers: boolean): Promise<boolean> {
    return true;
  }
}

export class Ch34xSerialDriver implements IUsbSerialDriver {
  private mDevice: usbManager.USBDevice;
  private mPort: IUsbSerialPort;

  constructor(device: usbManager.USBDevice) {
    this.mDevice = device;
    this.mPort = new Ch340SerialPort(device, 0, this);
  }

  getDevice(): usbManager.USBDevice {
    return this.mDevice;
  }

  getPorts(): IUsbSerialPort[] {
    return [this.mPort];
  }

  static getSupportedDevices(): Map<number, number[]> {
    const devices: Map<number, number[]> = new Map();
    devices.set(UsbId.VENDOR_QINHENG, [UsbId.QINHENG_HL340]);
    return devices;
  }
}
