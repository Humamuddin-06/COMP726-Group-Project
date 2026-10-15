// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title AUT Attendance Rewards
/// @notice Coursework prototype. No AUT affiliation or live integration.
/// @dev Students submit their own check-in; the assigned lecturer (or admin)
/// approves it. Approval is what credits points — there is no auto-approval.
/// Each student's attendance records are linked together (each new record
/// stores the hash of that student's previous record), so altering a past
/// record breaks the chain for that specific student and becomes detectable.
/// Wallet activity and attendance records are public on a public blockchain.
/// Keep student names, student IDs, and voucher secrets outside the blockchain.
/// @dev Future work: a points-redemption / reward marketplace (students
/// spending points on rewards via a merchant role) was scoped out of this
/// prototype to keep it achievable, and is noted as a future extension.
contract AUTAttendanceRewards {
    address public immutable admin;
    uint256 public constant POINTS_PER_CLASS = 10;

    struct Session {
        address lecturer;
        bool exists;
        bool open;
    }

    struct AttendanceRecord {
        uint256 sessionId;
        uint256 timestamp;
        bytes32 prevHash;   // hash of this student's previous record (0x0 if first)
        bytes32 recordHash; // hash of this record, becomes the next record's prevHash
        bool approved;
    }

    mapping(address => bool) public registeredStudents;
    mapping(address => bool) public lecturers;
    mapping(address => uint256) public points;
    mapping(uint256 => Session) public sessions;

    // Each student's own chain of attendance records, in order.
    mapping(address => AttendanceRecord[]) private studentChains;

    // Prevents a student submitting more than one check-in for the same session.
    mapping(uint256 => mapping(address => bool)) public hasCheckedIn;

    event StudentRegistered(address indexed student);
    event LecturerUpdated(address indexed lecturer, bool authorised);
    event SessionCreated(uint256 indexed sessionId, address indexed lecturer);
    event SessionClosed(uint256 indexed sessionId);
    event AttendanceSubmitted(address indexed student, uint256 indexed sessionId, uint256 recordIndex, bytes32 recordHash);
    event AttendanceApproved(address indexed student, uint256 indexed sessionId, uint256 recordIndex, uint256 pointsAwarded);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only the administrator can do this");
        _;
    }

    modifier onlyRegisteredStudent() {
        require(registeredStudents[msg.sender], "Student is not registered");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    // The administrator verifies student identity before registering a wallet.
    // Enforcing one wallet per real student requires an external register.
    function registerStudent(address student) external onlyAdmin {
        require(student != address(0), "Invalid student address");
        require(!registeredStudents[student], "Student already registered");
        registeredStudents[student] = true;
        emit StudentRegistered(student);
    }

    function setLecturer(address lecturer, bool authorised) external onlyAdmin {
        require(lecturer != address(0), "Invalid lecturer address");
        lecturers[lecturer] = authorised;
        emit LecturerUpdated(lecturer, authorised);
    }

    // Assign a unique positive number to each actual class meeting.
    // Only the administrator creates sessions to prevent invented sessions.
    function createSession(uint256 sessionId, address lecturer) external onlyAdmin {
        require(sessionId > 0, "Session ID must be positive");
        require(!sessions[sessionId].exists, "Session already exists");
        require(lecturers[lecturer], "Lecturer is not authorised");
        sessions[sessionId] = Session(lecturer, true, true);
        emit SessionCreated(sessionId, lecturer);
    }

    // Closing is permanent. Existing attendance and points remain intact.
    function closeSession(uint256 sessionId) external onlyAdmin {
        require(sessions[sessionId].exists && sessions[sessionId].open, "Session unavailable");
        sessions[sessionId].open = false;
        emit SessionClosed(sessionId);
    }

    /// @notice Student check-in step (mirrors the QR scan -> webpage submission).
    /// Creates a new Pending record linked to this student's previous one.
    function recordAttendance(uint256 sessionId) external onlyRegisteredStudent {
        Session storage session = sessions[sessionId];
        require(session.exists && session.open, "Session unavailable");
        require(!hasCheckedIn[sessionId][msg.sender], "Already checked in for this session");

        AttendanceRecord[] storage chain = studentChains[msg.sender];
        bytes32 prevHash = chain.length > 0 ? chain[chain.length - 1].recordHash : bytes32(0);
        bytes32 newHash = keccak256(abi.encode(msg.sender, sessionId, block.timestamp, prevHash));

        chain.push(AttendanceRecord({
            sessionId: sessionId,
            timestamp: block.timestamp,
            prevHash: prevHash,
            recordHash: newHash,
            approved: false
        }));
        hasCheckedIn[sessionId][msg.sender] = true;

        emit AttendanceSubmitted(msg.sender, sessionId, chain.length - 1, newHash);
    }

    /// @notice Lecturer approval step. Only the session's assigned lecturer or
    /// the admin can approve, and approving is what credits the reward points.
    function verifyAttendance(address student, uint256 recordIndex) external {
        AttendanceRecord[] storage chain = studentChains[student];
        require(recordIndex < chain.length, "Unknown record");
        AttendanceRecord storage record = chain[recordIndex];

        Session storage session = sessions[record.sessionId];
        require(
            msg.sender == admin || msg.sender == session.lecturer,
            "Only assigned lecturer or administrator"
        );
        require(!record.approved, "Record already approved");

        record.approved = true;
        points[student] += POINTS_PER_CLASS;

        emit AttendanceApproved(student, record.sessionId, recordIndex, POINTS_PER_CLASS);
    }

    /// @notice Read-only: a student's full, ordered attendance chain.
    function getStudentChain(address student) external view returns (AttendanceRecord[] memory) {
        return studentChains[student];
    }

    function getMyPoints() external view returns (uint256) {
        return points[msg.sender];
    }
}
