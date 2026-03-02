/**
 * CDC/ACM USB Serial Driver
 * Ported from usb-serial-for-android CdcAcmSerialDriver to HarmonyOS ArkTS
 */
import { usbManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { IUsbSerialDriver, IUsbSerialPort } from './IUsbSerial';
import { CommonUsbSerialPort } from './CommonUsbSerialPort';
import {
  PARITY_NONE, PARITY_ODD, PARITY_EVEN, PARITY_MARK, PARITY_SPACE,
  STOPBITS_1, STOPBITS_1_5, STOPBITS_2
} from './UsbSerialTypes';
import * as UsbId from './UsbId';

const TAG = 'CdcAcmSerialDriver';
const DOMAIN = 0x0000;

// ACM control request constants
const USB_RECIP_INTERFACE = 0x01;
const USB_RT_ACM = 0x20 | USB_RECIP_INTERFACE; // USB_TYPE_CLASS | USB_RECIP_INTERFACE
const SET_LINE_CODING = 0x20;
const GET_LINE_CODING = 0x21;
const SET_CONTROL_LINE_STATE = 0x22;
const SEND_BREAK = 0x23;

class CdcAcmSerialPort extends CommonUsbSerialPort {
  private mDriverRef: CdcAcmSerialDriver;
  private mControlInterface: usbManager.USBInterface | null = null;
  private mDataInterface: usbManager.USBInterface | null = null;
  private mControlEndpoint: usbManager.USBEndpoint | null = null;
  private mReadEndpoint: usbManager.USBEndpoint | null = null;
  private mWriteEndpoint: usbManager.USBEndpoint | null = null;
  private mRts: boolean = false;
  private mDtr: boolean = false;

  constructor(device: usbManager.USBDevice, portNumber: number, driver: CdcAcmSerialDriver) {
    super(device, portNumber);
    this.mDriverRef = driver;
  }

  getDriver(): IUsbSerialDriver {
    return this.mDriverRef;
  }

  async open(pipe: usbManager.USBDevicePipe): Promise<void> {
    if (this.mPipe !== null) {
      throw new Error('Already open');
    }
    this.mPipe = pipe;
    let opened = false;
    try {
      const configs = this.mDevice.configs;
      if (!configs || configs.length === 0) {
        throw new Error('No USB configurations found');
      }
      const interfaces = configs[0].interfaces;
      if (interfaces.length === 1) {
        hilog.info(DOMAIN, TAG, '%{public}s', 'Single interface device, using single interface logic');
        await this.openSingleInterface(interfaces[0]);
      } else {
        hilog.info(DOMAIN, TAG, '%{public}s', 'Multiple interfaces, using default interface logic');
        await this.openInterface(interfaces);
      }
      opened = true;
    } finally {
      if (!opened) {
        this.mPipe = null;
        this.mControlEndpoint = null;
        this.mReadEndpoint = null;
        this.mWriteEndpoint = null;
      }
    }
  }

  private async openSingleInterface(iface: usbManager.USBInterface): Promise<void> {
    this.mControlInterface = iface;
    this.mDataInterface = iface;
    if (usbManager.claimInterface(this.mPipe!, iface, true) !== 0) {
      throw new Error('Could not claim shared control/data interface.');
    }
    const endCount = iface.endpoints.length;
    if (endCount < 3) {
      throw new Error('Insufficient number of endpoints(' + endCount + ')');
    }
    this.mControlEndpoint = null;
    this.mReadEndpoint = null;
    this.mWriteEndpoint = null;
    for (let i = 0; i < endCount; i++) {
      const ep = iface.endpoints[i];
      if (ep.direction === 0x80 && ep.type === 3) {
        // USB_DIR_IN + interrupt
        this.mControlEndpoint = ep;
      } else if (ep.direction === 0x80 && ep.type === 2) {
        // USB_DIR_IN + bulk
        this.mReadEndpoint = ep;
      } else if (ep.direction === 0x00 && ep.type === 2) {
        // USB_DIR_OUT + bulk
        this.mWriteEndpoint = ep;
      }
      if (this.mControlEndpoint && this.mReadEndpoint && this.mWriteEndpoint) {
        break;
      }
    }
    if (!this.mControlEndpoint || !this.mReadEndpoint || !this.mWriteEndpoint) {
      throw new Error('Could not establish all endpoints');
    }
  }

  private async openInterface(interfaces: usbManager.USBInterface[]): Promise<void> {
    this.mControlInterface = interfaces[0];
    if (usbManager.claimInterface(this.mPipe!, this.mControlInterface, true) !== 0) {
      throw new Error('Could not claim control interface.');
    }
    this.mControlEndpoint = this.mControlInterface.endpoints[0];

    this.mDataInterface = interfaces[1];
    if (usbManager.claimInterface(this.mPipe!, this.mDataInterface, true) !== 0) {
      throw new Error('Could not claim data interface.');
    }
    this.mReadEndpoint = this.mDataInterface.endpoints[1];
    this.mWriteEndpoint = this.mDataInterface.endpoints[0];
  }

  async close(): Promise<void> {
    if (this.mPipe === null) {
      throw new Error('Already closed');
    }
    usbManager.closePipe(this.mPipe);
    this.mPipe = null;
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
    let stopBitsByte: number;
    if (stopBits === STOPBITS_1) {
      stopBitsByte = 0;
    } else if (stopBits === STOPBITS_1_5) {
      stopBitsByte = 1;
    } else if (stopBits === STOPBITS_2) {
      stopBitsByte = 2;
    } else {
      throw new Error('Bad value for stopBits: ' + stopBits);
    }

    let parityByte: number;
    if (parity === PARITY_NONE) {
      parityByte = 0;
    } else if (parity === PARITY_ODD) {
      parityByte = 1;
    } else if (parity === PARITY_EVEN) {
      parityByte = 2;
    } else if (parity === PARITY_MARK) {
      parityByte = 3;
    } else if (parity === PARITY_SPACE) {
      parityByte = 4;
    } else {
      throw new Error('Bad value for parity: ' + parity);
    }

    const msg = new Uint8Array(7);
    msg[0] = baudRate & 0xFF;
    msg[1] = (baudRate >> 8) & 0xFF;
    msg[2] = (baudRate >> 16) & 0xFF;
    msg[3] = (baudRate >> 24) & 0xFF;
    msg[4] = stopBitsByte;
    msg[5] = parityByte;
    msg[6] = dataBits & 0xFF;
    await this.sendAcmControlMessage(SET_LINE_CODING, 0, msg);
  }

  private async sendAcmControlMessage(request: number, value: number, buf: Uint8Array | null): Promise<number> {
    const length = buf ? buf.length : 0;
    return this.controlTransfer(USB_RT_ACM, request, value, 0, buf, length, 5000);
  }

  getCD(): boolean {
    return false;
  }

  getCTS(): boolean {
    return false;
  }

  getDSR(): boolean {
    return false;
  }

  getDTR(): boolean {
    return this.mDtr;
  }

  async setDTR(value: boolean): Promise<void> {
    this.mDtr = value;
    await this.setDtrRts();
  }

  getRI(): boolean {
    return false;
  }

  getRTS(): boolean {
    return this.mRts;
  }

  async setRTS(value: boolean): Promise<void> {
    this.mRts = value;
    await this.setDtrRts();
  }

  private async setDtrRts(): Promise<void> {
    const value = (this.mRts ? 0x2 : 0) | (this.mDtr ? 0x1 : 0);
    await this.sendAcmControlMessage(SET_CONTROL_LINE_STATE, value, null);
  }
}

export class CdcAcmSerialDriver implements IUsbSerialDriver {
  private mDevice: usbManager.USBDevice;
  private mPort: IUsbSerialPort;

  constructor(device: usbManager.USBDevice) {
    this.mDevice = device;
    this.mPort = new CdcAcmSerialPort(device, 0, this);
  }

  getDevice(): usbManager.USBDevice {
    return this.mDevice;
  }

  getPorts(): IUsbSerialPort[] {
    return [this.mPort];
  }

  static getSupportedDevices(): Map<number, number[]> {
    const devices: Map<number, number[]> = new Map();
    devices.set(UsbId.VENDOR_ARDUINO, [
      UsbId.ARDUINO_UNO,
      UsbId.ARDUINO_UNO_R3,
      UsbId.ARDUINO_MEGA_2560,
      UsbId.ARDUINO_MEGA_2560_R3,
      UsbId.ARDUINO_SERIAL_ADAPTER,
      UsbId.ARDUINO_SERIAL_ADAPTER_R3,
      UsbId.ARDUINO_MEGA_ADK,
      UsbId.ARDUINO_MEGA_ADK_R3,
      UsbId.ARDUINO_LEONARDO,
      UsbId.ARDUINO_MICRO
    ]);
    devices.set(UsbId.VENDOR_VAN_OOIJEN_TECH, [UsbId.VAN_OOIJEN_TECH_TEENSYDUINO_SERIAL]);
    devices.set(UsbId.VENDOR_ATMEL, [UsbId.ATMEL_LUFA_CDC_DEMO_APP]);
    devices.set(UsbId.VENDOR_LEAFLABS, [UsbId.LEAFLABS_MAPLE]);
    return devices;
  }
}
