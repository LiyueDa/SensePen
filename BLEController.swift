import Foundation
import CoreBluetooth
import UIKit

// MARK: - BLE Controller Delegate
protocol BLEControllerDelegate: AnyObject {
    func bleControllerDidConnect()
    func bleControllerDidDisconnect()
    func bleControllerDidUpdatePenPosition(_ position: CGPoint)
}

// MARK: - Service and Characteristic UUIDs (migrated from original code)
let SERVICE_UUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
let WRITE_CHARACTERISTIC_UUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")

let PWM: UInt8 = 255

// MARK: - BLE Controller for MagicPen Device (migrated from original code)
class BLEController: NSObject {
    
    // MARK: - Properties
    weak var delegate: BLEControllerDelegate?
    
    var centralManager: CBCentralManager!
    private(set) var peripheral: CBPeripheral?
    var writeCharacteristic: CBCharacteristic?  // Unified write characteristic for force feedback and vibration
    var onTargetReached: (() -> Void)?

    var pwmUpdateTimer: Timer?
    let pwmUpdateQueue = DispatchQueue(label: "com.magicpen.pwmUpdateQueue")
    
    var locationX = 0.0
    var locationY = 0.0
    var azimuthInDegrees = 0.0
    
    var TargetX = 0.0
    var TargetY = 0.0
    
    var shouldDrive = false
    
    // Vibration control properties
    var currentVibrationIntensity: UInt8 = 0
    var isVibrationEnabled = true
    
    // Current force motor state record
    var currentDutyCycle11: UInt8 = 0
    var currentDutyCycle12: UInt8 = 0
    var currentDutyCycle21: UInt8 = 0
    var currentDutyCycle22: UInt8 = 0

    // Connection state
    var isConnected: Bool {
        return peripheral?.state == .connected
    }
    
    // MARK: - Initialization
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
        print("🔵 BLE Controller initialized for MagicPen")
    }
    
    // MARK: - Public Methods
    
    /// Start scanning for MagicPen devices
    func startScan() {
        guard centralManager.state == .poweredOn else {
            print("⚠️ Bluetooth is not powered on")
            return
        }
        
        print("🔍 Scanning for MagicPen devices...")
        centralManager.scanForPeripherals(withServices: [SERVICE_UUID], options: nil)
        
        // Stop scanning after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            self.stopScan()
        }
    }
    
    /// Stop scanning
    func stopScan() {
        centralManager.stopScan()
        print("⏹️ Stopped scanning")
    }
    
    /// Disconnect from current device
    func disconnect() {
        guard let peripheral = peripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    // MARK: - Haptic Control Methods (migrated from original code)
    
    /// Restore the original sendCommand method (4 bytes, non-destructive)
    func sendCommand(duty_cycle11: UInt8, duty_cycle12: UInt8, duty_cycle21: UInt8, duty_cycle22: UInt8) {
        guard let characteristic = writeCharacteristic else {
            print("❌ writeCharacteristic not ready, cannot send force feedback command")
            return
        }
        
        // Update current force motor state
        currentDutyCycle11 = duty_cycle11
        currentDutyCycle12 = duty_cycle12
        currentDutyCycle21 = duty_cycle21
        currentDutyCycle22 = duty_cycle22
        
        let data = Data([duty_cycle11, duty_cycle12, duty_cycle21, duty_cycle22])
        peripheral?.writeValue(data, for: characteristic, type: .withoutResponse)
    }
    
    /// Send vibration command to MagicPen (using verified protocol)
    func sendVibration(intensity: UInt8, duration: TimeInterval) {
        guard isVibrationEnabled, let characteristic = writeCharacteristic else { 
            print("❌ Vibration conditions not met: isVibrationEnabled=\(isVibrationEnabled), writeCharacteristic=\(writeCharacteristic != nil)")
            return 
        }
        currentVibrationIntensity = intensity
        
        print("📳 Sending LRA vibration command, intensity: \(intensity)")
        print("📍 Using protocol [0xFF, 0x01, intensity] - verified vibration protocol")
        
        // Use verified vibration protocol
        let vibrationCommand = Data([0xFF, 0x01, intensity])
        peripheral?.writeValue(vibrationCommand, for: characteristic, type: .withoutResponse)
        print("📤 LRA vibration command: [0xFF, 0x01, \(intensity)]")
        
        // If duration is set, schedule forced stop
        if duration > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                self.stop() // Use forced stop method
            }
        }
    }
    
    /// Send force feedback command to MagicPen
    func sendForce(x: Double, y: Double, duration: TimeInterval) {
        guard let characteristic = writeCharacteristic else {
            print("⚠️ Force characteristic not available")
            return
        }
        
        // Convert force values to PWM values (0-255)
        let pwmX = UInt8(min(max(abs(x) * 255, 0), 255))
        let pwmY = UInt8(min(max(abs(y) * 255, 0), 255))
        
        // Determine direction flags
        let flagX = x > 0
        let flagY = y > 0
        
        sendPWM(PWMX: pwmX, flagX: flagX, PWMY: pwmY, flagY: flagY)
        
        // If duration specified, stop after duration
        if duration > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                self.stopForce()
            }
        }
        
        print("💪 Sent force: x=\(x), y=\(y), duration=\(duration)s")
    }
    
    /// Send combined vibration and force command
    func sendCombinedFeedback(vibrationIntensity: UInt8, forceX: Double, forceY: Double, duration: TimeInterval) {
        // Send force feedback first
        sendForce(x: forceX, y: forceY, duration: duration)
        
        // Send vibration with slight delay to avoid command collision
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            self.sendVibration(intensity: vibrationIntensity, duration: duration)
        }
    }
    
    /// Stop all haptic feedback
    func stopHaptics() {
        stop() // Use forced stop method to stop all vibration and force feedback at once
    }
    
    /// Stop vibration but keep force feedback
    func stopVibration() {
        guard let characteristic = writeCharacteristic else { return }
        
        // Use protocol stop command
        let stopCommand = Data([0xFF, 0x00, 0x00])
        peripheral?.writeValue(stopCommand, for: characteristic, type: .withoutResponse)
        print("📤 Sending vibration stop command: [0xFF, 0x00, 0x00]")
        
        currentVibrationIntensity = 0
    }
    
    /// Stop force feedback but keep vibration
    func stopForce() {
        sendCommand(duty_cycle11: 0, duty_cycle12: 0, duty_cycle21: 0, duty_cycle22: 0)
    }

    func sendPWM(PWMX: UInt8, flagX: Bool, PWMY: UInt8, flagY: Bool) {
        var duty_cycle11: UInt8 = 0
        var duty_cycle12: UInt8 = 0
        var duty_cycle21: UInt8 = 0
        var duty_cycle22: UInt8 = 0

        // Check flags and set appropriate duty cycles for X-axis
        if flagX { // Right movement
            duty_cycle11 = 0
            duty_cycle12 = PWMX
        } else {  // Left movement
            duty_cycle11 = PWMX
            duty_cycle12 = 0
        }

        // Check flags and set appropriate duty cycles for Y-axis
        if flagY { // Upward movement
            duty_cycle21 = 0
            duty_cycle22 = PWMY
        } else {  // Downward movement
            duty_cycle21 = PWMY
            duty_cycle22 = 0
        }
        
        sendCommand(duty_cycle11: duty_cycle11, duty_cycle12: duty_cycle12, duty_cycle21: duty_cycle21, duty_cycle22: duty_cycle22)
    }

    func stop() {
        guard let characteristic = writeCharacteristic else { 
            print("❌ writeCharacteristic not available for stop command")
            return 
        }
        
        // Force stop force feedback (immediately send all-zero command)
        let forceStopData = Data([0, 0, 0, 0])
        peripheral?.writeValue(forceStopData, for: characteristic, type: .withoutResponse)
        
        // Small delay to ensure command is sent (refer to original code)
        usleep(10000) // 0.01s, refer to original code's sleep(UInt32(0.01))
        
        // Force stop vibration (immediately send stop command)
        let vibrationStopData = Data([0xFF, 0x00, 0x00])
        peripheral?.writeValue(vibrationStopData, for: characteristic, type: .withoutResponse)
        
        // Another small delay to ensure stop command is sent
        usleep(10000) // 0.01s
        
        // Reset state
        currentVibrationIntensity = 0
        currentDutyCycle11 = 0
        currentDutyCycle12 = 0
        currentDutyCycle21 = 0
        currentDutyCycle22 = 0
        
        print("🛑 Force stop all vibration and force feedback - send all-zero command")
        print("📤 Force stop: [0,0,0,0] + [0xFF,0x00,0x00]")
    }
    
    /// Pen tip lift handler - implemented similar to Navigation project
    func didLiftPencil() {
        // Immediately stop motor drive, no delay (HapticContentReader requires instant response)
        shouldDrive = false
        stop()
        print("🖊️ The user lifts the pencil - stopped driving immediately")
    }
    
    // MARK: - Test Methods
    
    /// LRA vibration test method (migrated from original code)
    func testLRAVibration(intensity: UInt8) {
        guard let characteristic = writeCharacteristic else {
            print("❌ Characteristic not ready, cannot test LRA vibration")
            return
        }
        
        print("🧪 Starting LRA vibration test, intensity: \(intensity)")
        print("📍 Using verified protocol [0xFF, 0x01, intensity]")
        
        let vibrationCommand = Data([0xFF, 0x01, intensity])
        peripheral?.writeValue(vibrationCommand, for: characteristic, type: .withoutResponse)
        print("📤 Vibration command: [0xFF, 0x01, \(intensity)]")
        
        // Send stop command after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            let stopCommand = Data([0xFF, 0x00, 0x00])
            self.peripheral?.writeValue(stopCommand, for: characteristic, type: .withoutResponse)
            print("📤 Vibration stop command: [0xFF, 0x00, 0x00]")
            print("🛑 LRA vibration test completed")
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEController: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("🔵 Bluetooth powered on and ready")
        case .poweredOff:
            print("🔴 Bluetooth powered off")
        case .unauthorized:
            print("⚠️ Bluetooth access unauthorized")
        case .unsupported:
            print("⚠️ Bluetooth not supported on this device")
        case .resetting:
            print("🔄 Bluetooth resetting")
        case .unknown:
            print("❓ Bluetooth state unknown")
        @unknown default:
            print("❓ Unknown bluetooth state")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("📡 Discovered device: \(peripheral.name ?? "Unknown") RSSI: \(RSSI)")
        
        // Connect to the first MagicPen device found (migrated from original code)
        if let name = peripheral.name, name.contains("MagicPen") {
            print("✅ Found MagicPen device, connecting...")
            self.peripheral = peripheral
            peripheral.delegate = self
            centralManager.stopScan()
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ Connected to MagicPen: \(peripheral.name ?? "Unknown")")
        
        // Discover services
        peripheral.discoverServices([SERVICE_UUID])
        
        delegate?.bleControllerDidConnect()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("❌ Disconnected from MagicPen")
        
        if let error = error {
            print("Disconnection error: \(error.localizedDescription)")
        }
        
        self.peripheral = nil
        writeCharacteristic = nil
        
        delegate?.bleControllerDidDisconnect()
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("❌ Failed to connect to MagicPen")
        
        if let error = error {
            print("Connection error: \(error.localizedDescription)")
        }
        
        self.peripheral = nil
    }
}

// MARK: - CBPeripheralDelegate
extension BLEController: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("❌ Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            print("🔍 Found service: \(service.uuid)")
            if service.uuid == SERVICE_UUID {
                peripheral.discoverCharacteristics([WRITE_CHARACTERISTIC_UUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("❌ Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            print("🔍 Found characteristic: \(characteristic.uuid)")
            
            if characteristic.uuid == WRITE_CHARACTERISTIC_UUID {
                writeCharacteristic = characteristic
                print("✅ Write characteristic ready for force feedback and vibration")
                
                // Configure haptic library with this controller
                // Note: This will be handled by MainViewController
                print("✅ Write characteristic ready for force feedback and vibration")
                
                print("🎉 MagicPen fully configured and ready for haptic feedback!")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ Error writing to characteristic: \(error.localizedDescription)")
        }
    }
} 