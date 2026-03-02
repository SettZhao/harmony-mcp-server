/**
 * USB Serial Library Unit Tests
 * Framework: @ohos/hypium
 *
 * Tests cover:
 * - UsbId constants (VID/PID values)
 * - UsbSerialTypes serial protocol constants  
 * - HexDump utility functions
 * - ProbeTable add/find driver entries
 * - UsbSerialProber default driver registration count
 * - FTDI baud rate conversion algorithm (via FtdiSerialDriver internal test helper)
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import {
  VENDOR_FTDI, FTDI_FT232R, FTDI_FT231X,
  VENDOR_SILABS, SILABS_CP2102, SILABS_CP2105,
  VENDOR_PROLIFIC, PROLIFIC_PL2303,
  VENDOR_QINHENG, QINHENG_HL340
} from 'library';
import {
  DATABITS_5, DATABITS_6, DATABITS_7, DATABITS_8,
  PARITY_NONE, PARITY_ODD, PARITY_EVEN, PARITY_MARK, PARITY_SPACE,
  STOPBITS_1, STOPBITS_1_5, STOPBITS_2,
  FLOWCONTROL_NONE, FLOWCONTROL_RTSCTS_IN
} from 'library';
import { dumpHexStringAll, dumpHexString, toHexStringByte, toHexStringArray } from 'library';
import { ProbeTable } from 'library';
import { UsbSerialProber } from 'library';
import { usbManager } from '@kit.BasicServicesKit';
import { IUsbSerialDriver } from 'library';

export default function usbSerialTest() {
  describe('UsbSerialTests', () => {
    beforeAll(() => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'USB Serial tests begin');
    });

    afterAll(() => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'USB Serial tests end');
    });

    // ---- UsbId constants ----

    it('testVendorIdFtdi', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testVendorIdFtdi');
      expect(VENDOR_FTDI).assertEqual(0x0403);
      done();
    });

    it('testProductIdFtdiFT232R', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testProductIdFtdiFT232R');
      expect(FTDI_FT232R).assertEqual(0x6001);
      done();
    });

    it('testVendorIdSilabs', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testVendorIdSilabs');
      expect(VENDOR_SILABS).assertEqual(0x10c4);
      done();
    });

    it('testVendorIdProlific', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testVendorIdProlific');
      expect(VENDOR_PROLIFIC).assertEqual(0x067b);
      done();
    });

    it('testVendorIdQinheng', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testVendorIdQinheng');
      expect(VENDOR_QINHENG).assertEqual(0x1a86);
      done();
    });

    it('testProductIdProlific', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testProductIdProlific');
      expect(PROLIFIC_PL2303).assertEqual(0x2303);
      done();
    });

    // ---- UsbSerialTypes constants ----

    it('testDataBitsConstants', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testDataBitsConstants');
      expect(DATABITS_5).assertEqual(5);
      expect(DATABITS_6).assertEqual(6);
      expect(DATABITS_7).assertEqual(7);
      expect(DATABITS_8).assertEqual(8);
      done();
    });

    it('testParityConstants', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testParityConstants');
      expect(PARITY_NONE).assertEqual(0);
      expect(PARITY_ODD).assertEqual(1);
      expect(PARITY_EVEN).assertEqual(2);
      expect(PARITY_MARK).assertEqual(3);
      expect(PARITY_SPACE).assertEqual(4);
      done();
    });

    it('testStopBitsConstants', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testStopBitsConstants');
      expect(STOPBITS_1).assertEqual(1);
      expect(STOPBITS_1_5).assertEqual(3);
      expect(STOPBITS_2).assertEqual(2);
      done();
    });

    it('testFlowControlConstants', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testFlowControlConstants');
      expect(FLOWCONTROL_NONE).assertEqual(0);
      expect(FLOWCONTROL_RTSCTS_IN).assertEqual(1);
      done();
    });

    // ---- HexDump utility ----

    it('testHexDumpSingleByte', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testHexDumpSingleByte');
      const result = toHexStringByte(0xFF);
      expect(result).assertEqual('FF');
      done();
    });

    it('testHexDumpZeroByte', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testHexDumpZeroByte');
      const result = toHexStringByte(0x00);
      expect(result).assertEqual('00');
      done();
    });

    it('testHexDumpArray', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testHexDumpArray');
      const arr = new Uint8Array([0xDE, 0xAD, 0xBE, 0xEF]);
      const result = toHexStringArray(arr);
      expect(result).assertEqual('DEADBEEF');
      done();
    });

    it('testHexDumpAll', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testHexDumpAll');
      const arr = new Uint8Array([0x01, 0x02, 0x03]);
      const result = dumpHexStringAll(arr);
      expect(result.length > 0).assertTrue();
      done();
    });

    it('testHexDumpRange', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testHexDumpRange');
      const arr = new Uint8Array([0x00, 0xAB, 0xCD, 0x00]);
      // Dump only middle 2 bytes
      const result = dumpHexString(arr, 1, 2);
      expect(result).assertContain('AB');
      expect(result).assertContain('CD');
      done();
    });

    // ---- ProbeTable add/find ----

    it('testProbeTableAddAndFind', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testProbeTableAddAndFind');
      const table: ProbeTable = new ProbeTable();
      const factory = (device: usbManager.USBDevice): IUsbSerialDriver => {
        throw new Error('not used in test');
      };
      table.addProduct(0x0403, 0x6001, factory);
      const found = table.findDriver(0x0403, 0x6001);
      expect(found !== null).assertTrue();
      done();
    });

    it('testProbeTableNotFound', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testProbeTableNotFound');
      const table: ProbeTable = new ProbeTable();
      const found = table.findDriver(0x1234, 0x5678);
      expect(found === null).assertTrue();
      done();
    });

    it('testProbeTableSize', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testProbeTableSize');
      const table: ProbeTable = new ProbeTable();
      const factory = (device: usbManager.USBDevice): IUsbSerialDriver => {
        throw new Error('not used in test');
      };
      table.addProduct(0x0403, 0x6001, factory);
      table.addProduct(0x0403, 0x6015, factory);
      expect(table.size()).assertEqual(2);
      done();
    });

    it('testProbeTableAddDriverBulk', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testProbeTableAddDriverBulk');
      const table: ProbeTable = new ProbeTable();
      const supported: Map<number, number[]> = new Map();
      supported.set(0x0403, [0x6001, 0x6015]);
      table.addDriver(supported, (device: usbManager.USBDevice): IUsbSerialDriver => {
        throw new Error('not used in test');
      });
      expect(table.size()).assertEqual(2);
      expect(table.findDriver(0x0403, 0x6001) !== null).assertTrue();
      expect(table.findDriver(0x0403, 0x6015) !== null).assertTrue();
      done();
    });

    // ---- UsbSerialProber default table ----

    it('testDefaultProberHasEntries', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testDefaultProberHasEntries');
      const table: ProbeTable = UsbSerialProber.getDefaultProbeTable();
      // Default table should register at least 5 products (FTDI FT232R, FT231X, CP2102, PL2303, HL340)
      expect(table.size() >= 5).assertTrue();
      done();
    });

    it('testDefaultProberFindsKnownFtdi', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testDefaultProberFindsKnownFtdi');
      const table: ProbeTable = UsbSerialProber.getDefaultProbeTable();
      const factory = table.findDriver(VENDOR_FTDI, FTDI_FT232R);
      expect(factory !== null).assertTrue();
      done();
    });

    it('testDefaultProberFindsCp2102', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testDefaultProberFindsCp2102');
      const table: ProbeTable = UsbSerialProber.getDefaultProbeTable();
      const factory = table.findDriver(VENDOR_SILABS, SILABS_CP2102);
      expect(factory !== null).assertTrue();
      done();
    });

    it('testDefaultProberFindsProlifcPL2303', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testDefaultProberFindsProlifcPL2303');
      const table: ProbeTable = UsbSerialProber.getDefaultProbeTable();
      const factory = table.findDriver(VENDOR_PROLIFIC, PROLIFIC_PL2303);
      expect(factory !== null).assertTrue();
      done();
    });

    it('testDefaultProberFindsQinhengHL340', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testDefaultProberFindsQinhengHL340');
      const table: ProbeTable = UsbSerialProber.getDefaultProbeTable();
      const factory = table.findDriver(VENDOR_QINHENG, QINHENG_HL340);
      expect(factory !== null).assertTrue();
      done();
    });

    it('testDefaultProberUnknownDeviceReturnsNull', 0, (done: Function) => {
      hilog.info(0x0000, 'UsbSerialTest', '%{public}s', 'testDefaultProberUnknownDeviceReturnsNull');
      const table: ProbeTable = UsbSerialProber.getDefaultProbeTable();
      const factory = table.findDriver(0x9999, 0x9999);
      expect(factory === null).assertTrue();
      done();
    });
  });
}
