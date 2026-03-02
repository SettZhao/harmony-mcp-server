/**
 * FTDI USB Serial Driver (FT232R, FT231X)
 * Ported from usb-serial-for-android FtdiSerialDriver to HarmonyOS ArkTS
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

const TAG = 'FtdiSerialDriver';
const DOMAIN = 0x0000;

// FTDI request type
const FTDI_DEVICE_OUT_REQTYPE = 0x40; // USB_TYPE_VENDOR | USB_RECIP_DEVICE | USB_ENDPOINT_OUT
const FTDI_DEVICE_IN_REQTYPE = 0xC0;  // USB_TYPE_VENDOR | USB_RECIP_DEVICE | USB_ENDPOINT_IN

// FTDI request codes
const SIO_RESET_REQUEST = 0;
const SIO_MODEM_CTRL_REQUEST = 1;
const SIO_SET_FLOW_CTRL_REQUEST = 2;
const SIO_SET_BAUD_RATE_REQUEST = 3;
const SIO_SET_DATA_REQUEST = 4;

const SIO_RESET_SIO = 0;
const SIO_RESET_PURGE_RX = 1;
const SIO_RESET_PURGE_TX = 2;

const MODEM_STATUS_HEADER_LENGTH = 2;

const USB_WRITE_TIMEOUT_MILLIS = 5000;
const USB_READ_TIMEOUT_MILLIS = 5000;

// Device type (simplified, just support TYPE_R like original)
const TYPE_R = 3;
const TYPE_AM = 0;
const TYPE_BM = 1;
const TYPE_2232C = 2;
const TYPE_2232H = 4;
const TYPE_4232H = 5;

class FtdiSerialPort extends CommonUsbSerialPort {
  private mDriverRef: FtdiSerialDriver;
  private mType: number = TYPE_R;
  private mMaxPacketSize: number = 64;

  constructor(device: usbManager.USBDevice, portNumber: number, driver: FtdiSerialDriver) {
    super(device, portNumber);
    this.mDriverRef = driver;
  }

  getDriver(): IUsbSerialDriver {
    return this.mDriverRef;
  }

  /**
   * Filter FTDI 2-byte modem status header from each USB packet
   */
  private filterStatusBytes(src: Uint8Array, dest: Uint8Array, totalBytesRead: number, maxPacketSize: number): number {
    const packetsCount = Math.floor(totalBytesRead / maxPacketSize) + (totalBytesRead % maxPacketSize === 0 ? 0 : 1);
    for (let packetIdx = 0; packetIdx < packetsCount; packetIdx++) {
      const count = (packetIdx === (packetsCount - 1))
        ? (totalBytesRead % maxPacketSize) - MODEM_STATUS_HEADER_LENGTH
        : maxPacketSize - MODEM_STATUS_HEADER_LENGTH;
      if (count > 0) {
        const srcOff = packetIdx * maxPacketSize + MODEM_STATUS_HEADER_LENGTH;
        const destOff = packetIdx * (maxPacketSize - MODEM_STATUS_HEADER_LENGTH);
        dest.set(src.subarray(srcOff, srcOff + count), destOff);
      }
    }
    return totalBytesRead - (packetsCount * 2);
  }

  async reset(): Promise<void> {
    const result = await this.controlTransfer(
      FTDI_DEVICE_OUT_REQTYPE, SIO_RESET_REQUEST, SIO_RESET_SIO, 0, null, 0, USB_WRITE_TIMEOUT_MILLIS
    );
    if (result !== 0) {
      throw new Error('Reset failed: result=' + result);
    }
    this.mType = TYPE_R;
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
        throw new Error('No USB configurations');
      }
      const interfaces = configs[0].interfaces;
      for (let i = 0; i < interfaces.length; i++) {
        if (usbManager.claimInterface(this.mPipe, interfaces[i], true) !== 0) {
          throw new Error('Error claiming interface ' + i);
        }
      }
      await this.reset();
      opened = true;
    } finally {
      if (!opened) {
        if (this.mPipe) {
          usbManager.closePipe(this.mPipe);
        }
        this.mPipe = null;
      }
    }
  }

  async close(): Promise<void> {
    if (this.mPipe === null) {
      throw new Error('Already closed');
    }
    usbManager.closePipe(this.mPipe);
    this.mPipe = null;
  }

  async read(dest: Uint8Array, timeoutMillis: number): Promise<number> {
    const configs = this.mDevice.configs;
    if (!configs || configs.length === 0) {
      throw new Error('No USB configurations');
    }
    const endpoint = configs[0].interfaces[0].endpoints[0];
    const readAmt = Math.min(dest.length, this.mReadBuffer.length);
    const readBuf = this.mReadBuffer.subarray(0, readAmt);
    const totalBytesRead = await this.bulkTransfer(endpoint, readBuf, timeoutMillis);
    if (totalBytesRead < MODEM_STATUS_HEADER_LENGTH) {
      throw new Error('Expected at least ' + MODEM_STATUS_HEADER_LENGTH + ' bytes');
    }
    return this.filterStatusBytes(this.mReadBuffer, dest, totalBytesRead, endpoint.maxPacketSize);
  }

  async write(src: Uint8Array, timeoutMillis: number): Promise<number> {
    const configs = this.mDevice.configs;
    if (!configs || configs.length === 0) {
      throw new Error('No USB configurations');
    }
    const endpoint = configs[0].interfaces[0].endpoints[1];
    let offset = 0;
    while (offset < src.length) {
      const writeLength = Math.min(src.length - offset, this.mWriteBuffer.length);
      const writeBuffer = offset === 0 ? src.subarray(0, writeLength) : (() => {
        this.mWriteBuffer.set(src.subarray(offset, offset + writeLength), 0);
        return this.mWriteBuffer.subarray(0, writeLength);
      })();
      const amtWritten = await this.bulkTransfer(endpoint, writeBuffer, timeoutMillis);
      if (amtWritten <= 0) {
        throw new Error('Error writing ' + writeLength + ' bytes at offset ' + offset);
      }
      offset += amtWritten;
    }
    return offset;
  }

  private async setBaudRate(baudRate: number): Promise<number> {
    const vals = this.convertBaudrate(baudRate);
    const actualBaudrate = vals[0];
    const index = vals[1];
    const value = vals[2];
    const result = await this.controlTransfer(
      FTDI_DEVICE_OUT_REQTYPE, SIO_SET_BAUD_RATE_REQUEST, value, index, null, 0, USB_WRITE_TIMEOUT_MILLIS
    );
    if (result !== 0) {
      throw new Error('Setting baudrate failed: result=' + result);
    }
    return actualBaudrate;
  }

  async setParameters(baudRate: number, dataBits: number, stopBits: number, parity: number): Promise<void> {
    await this.setBaudRate(baudRate);

    let config = dataBits;
    if (parity === PARITY_NONE) {
      config |= (0x00 << 8);
    } else if (parity === PARITY_ODD) {
      config |= (0x01 << 8);
    } else if (parity === PARITY_EVEN) {
      config |= (0x02 << 8);
    } else if (parity === PARITY_MARK) {
      config |= (0x03 << 8);
    } else if (parity === PARITY_SPACE) {
      config |= (0x04 << 8);
    } else {
      throw new Error('Unknown parity value: ' + parity);
    }

    if (stopBits === STOPBITS_1) {
      config |= (0x00 << 11);
    } else if (stopBits === STOPBITS_1_5) {
      config |= (0x01 << 11);
    } else if (stopBits === STOPBITS_2) {
      config |= (0x02 << 11);
    } else {
      throw new Error('Unknown stopBits value: ' + stopBits);
    }

    const result = await this.controlTransfer(
      FTDI_DEVICE_OUT_REQTYPE, SIO_SET_DATA_REQUEST, config, 0, null, 0, USB_WRITE_TIMEOUT_MILLIS
    );
    if (result !== 0) {
      throw new Error('Setting parameters failed: result=' + result);
    }
  }

  private convertBaudrate(baudrate: number): number[] {
    let divisor = Math.floor(24000000 / baudrate);
    let bestDivisor = 0;
    let bestBaud = 0;
    let bestBaudDiff = 0;
    const fracCode = [0, 3, 2, 4, 1, 5, 6, 7];

    for (let i = 0; i < 2; i++) {
      let tryDivisor = divisor + i;
      let baudEstimate: number;
      let baudDiff: number;

      if (tryDivisor <= 8) {
        tryDivisor = 8;
      } else if (tryDivisor < 12) {
        tryDivisor = 12;
      } else if (divisor < 16) {
        tryDivisor = 16;
      } else {
        if (tryDivisor > 0x1FFFF) {
          tryDivisor = 0x1FFFF;
        }
      }

      baudEstimate = Math.floor((24000000 + Math.floor(tryDivisor / 2)) / tryDivisor);
      baudDiff = Math.abs(baudEstimate - baudrate);

      if (i === 0 || baudDiff < bestBaudDiff) {
        bestDivisor = tryDivisor;
        bestBaud = baudEstimate;
        bestBaudDiff = baudDiff;
        if (baudDiff === 0) {
          break;
        }
      }
    }

    let encodedDivisor = (bestDivisor >> 3) | (fracCode[bestDivisor & 7] << 14);
    if (encodedDivisor === 1) {
      encodedDivisor = 0;
    } else if (encodedDivisor === 0x4001) {
      encodedDivisor = 1;
    }

    const value = encodedDivisor & 0xFFFF;
    const index = (encodedDivisor >> 16) & 0xFFFF;

    return [bestBaud, index, value];
  }

  getCD(): boolean { return false; }
  getCTS(): boolean { return false; }
  getDSR(): boolean { return false; }
  getDTR(): boolean { return false; }

  async setDTR(value: boolean): Promise<void> {
    // Not implemented for FT232R
  }

  getRI(): boolean { return false; }
  getRTS(): boolean { return false; }

  async setRTS(value: boolean): Promise<void> {
    // Not implemented for FT232R
  }

  async purgeHwBuffers(purgeReadBuffers: boolean, purgeWriteBuffers: boolean): Promise<boolean> {
    if (purgeReadBuffers) {
      const result = await this.controlTransfer(
        FTDI_DEVICE_OUT_REQTYPE, SIO_RESET_REQUEST, SIO_RESET_PURGE_RX, 0, null, 0, USB_WRITE_TIMEOUT_MILLIS
      );
      if (result !== 0) {
        throw new Error('Flushing RX failed: result=' + result);
      }
    }
    if (purgeWriteBuffers) {
      const result = await this.controlTransfer(
        FTDI_DEVICE_OUT_REQTYPE, SIO_RESET_REQUEST, SIO_RESET_PURGE_TX, 0, null, 0, USB_WRITE_TIMEOUT_MILLIS
      );
      if (result !== 0) {
        throw new Error('Flushing TX failed: result=' + result);
      }
    }
    return true;
  }
}

export class FtdiSerialDriver implements IUsbSerialDriver {
  private mDevice: usbManager.USBDevice;
  private mPort: IUsbSerialPort;

  constructor(device: usbManager.USBDevice) {
    this.mDevice = device;
    this.mPort = new FtdiSerialPort(device, 0, this);
  }

  getDevice(): usbManager.USBDevice {
    return this.mDevice;
  }

  getPorts(): IUsbSerialPort[] {
    return [this.mPort];
  }

  static getSupportedDevices(): Map<number, number[]> {
    const devices: Map<number, number[]> = new Map();
    devices.set(UsbId.VENDOR_FTDI, [UsbId.FTDI_FT232R, UsbId.FTDI_FT231X]);
    return devices;
  }
}
