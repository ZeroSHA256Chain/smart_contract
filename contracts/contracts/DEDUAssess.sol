// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract DEDUAssess {
    struct Project {
        string name;
        string description;
        uint256 deadline;
        address mentor;
        mapping(address => bool) verifiers;
        mapping(address => bool) allowedStudents; // only allowed students can send ther tasks
        bool isRestricted;
        bool allowResubmission;
    }

    struct ProjectView {
        string name;
        string description;
        uint256 deadline;
        address mentor;
        bool isRestricted;
        bool allowResubmission;
    }

    struct Submission {
        bytes32 taskHash;
        bool isVerified;
        bool isRejected;
        uint8 grade; // 0-100
    }

    mapping(uint256 => Project) private projects;
    mapping(uint256 => mapping(address => Submission)) public submissions;
    mapping(bytes32 => bool) public verifiedTasks;

    uint256 public projectCount;

    event ProjectCreated(uint256 projectId, string name, address mentor);
    event TaskSubmitted(uint256 projectId, address student, bytes32 taskHash);
    event TaskVerified(uint256 projectId, address student, bytes32 taskHash, uint8 grade);
    event TaskRejected(uint256 projectId, address student);

    modifier onlyVerifier(uint256 projectId) {
        require(isVerifier(projectId, msg.sender), "Not a verifier");
        _;
    }

    modifier onlyAllowedStudent(uint256 projectId) {
        require(isAllowedStudent(projectId, msg.sender), "Not allowed to submit");
        _;
    }

    modifier projectExists(uint256 projectId) {
        require(projectCount >= projectId + 1, "Project does not exists");
        _;
    }

    modifier submissionExists(uint256 projectId, address student) {
        require(submissions[projectId][student].taskHash != bytes32(0), "Submission does not exist");
        _;
    }

    function isVerifier(uint256 projectId, address user) public view returns (bool) {
        if (projects[projectId].mentor == user) return true;
        return projects[projectId].verifiers[user];
    }

    function isAllowedStudent(uint256 projectId, address student) public view returns (bool) {
        if (projectCount >= projectId + 1 && !projects[projectId].isRestricted) return true;
        return projects[projectId].allowedStudents[student];
    }

    function requireSubmissionPending(Submission memory submission) internal pure {
        require(!submission.isVerified, "Task already verified");
        require(!submission.isRejected, "Task already rejected");
    }

    function createProject(
        string memory name,
        string memory description,
        uint256 deadline,
        bool allowResubmission,
        address[] memory verifiers,
        address[] memory allowedStudents
    ) public {
        require(block.timestamp < deadline, "Invalid deadline");

        uint256 projectId = projectCount++;
        projects[projectId].name = name;
        projects[projectId].description = description;
        projects[projectId].deadline = deadline;
        projects[projectId].mentor = msg.sender;
        projects[projectId].isRestricted = allowedStudents.length > 0;
        projects[projectId].allowResubmission = allowResubmission;

        for (uint256 i = 0; i < verifiers.length; i++) {
            projects[projectId].verifiers[verifiers[i]] = true;
        }

        for (uint256 i = 0; i < allowedStudents.length; i++) {
            projects[projectId].allowedStudents[allowedStudents[i]] = true;
        }

        emit ProjectCreated(projectId, name, msg.sender);
    }

    function submitTask(
        uint256 projectId,
        bytes32 taskHash
    ) public projectExists(projectId) onlyAllowedStudent(projectId) {
        require(block.timestamp <= projects[projectId].deadline, "Deadline passed");

        if (!projects[projectId].allowResubmission) {
            require(submissions[projectId][msg.sender].taskHash == bytes32(0), "Resubmission not allowed");
        }

        require(!submissions[projectId][msg.sender].isVerified, "Task already verified");

        submissions[projectId][msg.sender] = Submission(taskHash, false, false, 0);
        emit TaskSubmitted(projectId, msg.sender, taskHash);
    }

    function verifyTask(
        uint256 projectId,
        address student,
        uint8 grade
    ) public projectExists(projectId) onlyVerifier(projectId) submissionExists(projectId, student) {
        require(grade <= 100, "Invalid grade");

        Submission storage submission = submissions[projectId][student];
        requireSubmissionPending(submission);

        submission.isVerified = true;
        submission.grade = grade;
        verifiedTasks[submission.taskHash] = true;

        emit TaskVerified(projectId, student, submission.taskHash, grade);
    }

    function rejectTask(
        uint256 projectId,
        address student
    ) public projectExists(projectId) onlyVerifier(projectId) submissionExists(projectId, student) {
        Submission storage submission = submissions[projectId][student];
        requireSubmissionPending(submission);

        submissions[projectId][student].isRejected = true;

        emit TaskRejected(projectId, student);
    }

    function checkTaskVerified(bytes32 taskHash) public view returns (bool) {
        return verifiedTasks[taskHash];
    }

    function getSubmission(
        uint256 projectId,
        address student
    ) public view projectExists(projectId) submissionExists(projectId, student) returns (Submission memory) {
        return submissions[projectId][student];
    }

    function getProject(
        uint256 projectId
    ) public view projectExists(projectId) returns (ProjectView memory) {
        return ProjectView(
            projects[projectId].name,
            projects[projectId].description,
            projects[projectId].deadline,
            projects[projectId].mentor,
            projects[projectId].isRestricted,
            projects[projectId].allowResubmission
        );
    }
}
