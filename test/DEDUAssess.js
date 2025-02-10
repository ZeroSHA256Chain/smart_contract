const { expect } = require("chai");
const { time, loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("DEDUAssess", function () {
     async function deploy() {
        [mentor, verifier1, verifier2, student1, student2, student3 ] = await ethers.getSigners();
        const deadline = (await time.latest()) + 86400 * 7; // 7 days later
        const taskHash = ethers.keccak256(ethers.toUtf8Bytes("Task 1"));

        const Assess = await ethers.getContractFactory("DEDUAssess");
        const contract = await Assess.deploy()

        return { contract, deadline, taskHash, mentor, verifier1, verifier2, student1, student2, student3 };
    }

    describe("Project Creation", function () {
        it("Should create a project with a mentor, verifiers and students", async function () {
            const { contract, deadline } =  await loadFixture(deploy);
            const verifiers = [verifier1, verifier2];
            const allowedStudents = [student1, student2];

            await contract.createProject(
                "Project 1",
                "Description of Project 1",
                deadline,
                false,
                verifiers,
                allowedStudents
            );

            const projectCount = await contract.projectCount();
            expect(projectCount).to.equal(1);

            const project = await contract.getProject(0);
            expect(project.name).to.equal("Project 1");
            expect(project.mentor).to.equal(mentor.address);
            expect(project.isRestricted).to.equal(true);
            expect(project.allowResubmission).to.equal(false);

            for (let i = 0; i < verifiers.length; i++) {
                expect(await contract.isVerifier(0, verifiers[i])).to.be.true;
            }
            expect(await contract.isVerifier(0, allowedStudents[0])).to.be.false;

            for (let i = 0; i < allowedStudents.length; i++) {
                expect(await contract.isAllowedStudent(0, allowedStudents[i])).to.be.true;
            }
            expect(await contract.isAllowedStudent(0, verifiers[0])).to.be.false;
        });

        it("Should reverts if deadline in the past", async function () {
            const { contract } =  await loadFixture(deploy);

            expect(
                contract.createProject(
                    "Project 1",
                    "Description of Project 1",
                    0,
                    false,
                    [],
                    []
                )
            ).to.be.revertedWith("Invalid deadline");
        });

    it("Should revert getting non-existent project", async function () {
            const { contract } =  await loadFixture(deploy);

            expect(contract.getProject(0)).to.be.revertedWith("Project does not exists");
        });
    });

    describe("Task Submission", function () {
        it("Should allow everyone to submit a task", async function () {
            const { contract, deadline, taskHash } =  await loadFixture(deploy);

            await contract.createProject(
                "Project 1",
                "Description",
                deadline,
                false,
                [],
                []
            );

            await expect(contract.connect(student1).submitTask(0, taskHash))
                .to.emit(contract, "TaskSubmitted")
                .withArgs(0, student1.address, taskHash);
        });

        it("Should allow allowed students to submit a task", async function () {
            const { contract, deadline, taskHash } =  await loadFixture(deploy);

            await contract.createProject(
                "Project 1",
                "Description",
                deadline,
                false,
                [],
                [student1]
            );

            await expect(contract.connect(student1).submitTask(0, taskHash))
                .to.emit(contract, "TaskSubmitted")
                .withArgs(0, student1.address, taskHash);
        });

        it("Should revert non-allowed student to submit a task", async function () {
            const { contract, deadline, taskHash } =  await loadFixture(deploy);

            await contract.createProject(
                "Project 1",
                "Description",
                deadline,
                false,
                [],
                [student1]
            );

            await expect(contract.connect(student2).submitTask(0, taskHash))
                .to.be.revertedWith("Not allowed to submit");
        });

        it("Should revert submitting a task after the deadline", async function () {
            const { contract, deadline, taskHash } =  await loadFixture(deploy);

            await contract.createProject(
                "Project 1",
                "Description",
                deadline,
                false,
                [],
                []
            );

            await time.increase(86400 * 8);
            await expect(contract.connect(student1).submitTask(0, taskHash))
                .to.revertedWith("Deadline passed");
        })

        it("Should allow resubmission if enabled", async function () {
            const { contract, deadline, taskHash } =  await loadFixture(deploy);

            await contract.createProject(
                "Project 1",
                "Description",
                deadline,
                true,
                [],
                []
            );

            await contract.connect(student1).submitTask(0, taskHash)
            await expect(contract.connect(student1).submitTask(0, taskHash))
                .to.emit(contract, "TaskSubmitted")
                .withArgs(0, student1.address, taskHash);
        });

        it("Should revert resubmission if disabled", async function () {
            const { contract, deadline, taskHash } =  await loadFixture(deploy);

            await contract.createProject(
                "Project 1",
                "Description",
                deadline,
                false,
                [],
                []
            );
            await contract.connect(student1).submitTask(0, taskHash);
            await expect(contract.connect(student1).submitTask(0, taskHash))
                .to.be.revertedWith("Resubmission not allowed");
        });

        it("Should revert submission if task is already verified", async function () {
            const { contract, deadline, taskHash } =  await loadFixture(deploy);

            await contract.createProject(
                "Project 1",
                "Description",
                deadline,
                true,  // resubmission allowed
                [],
                []
            );
            await contract.connect(student1).submitTask(0, taskHash);
            await contract.verifyTask(0, student1.address, 85);

            await expect(contract.connect(student1).submitTask(0, taskHash))
                .to.be.revertedWith("Task already verified");
        });
    });

    describe("Task Verification and Rejection", function () {
        it("Should allow verifiers to verify a task", async function () {
            const { contract, deadline, taskHash } =  await loadFixture(deploy);

            await contract.createProject(
                "Project 1",
                "Description",
                deadline,
                false,
                [verifier1],
                []
            );
            expect(await contract.verifiedTasks(taskHash)).to.equal(0);

            await contract.connect(student1).submitTask(0, taskHash);

            await expect(contract.connect(verifier1).verifyTask(0, student1.address, 90))
                .to.emit(contract, "TaskVerified")
                .withArgs(0, student1.address, taskHash, 90);

            const submission = await contract.getSubmission(0, student1.address);
            expect(submission.isVerified).to.be.true
            expect(submission.isRejected).to.be.false
            expect(submission.grade).to.equal(90);

            expect(await contract.verifiedTasks(taskHash)).to.equal(90);
        });

        it("Should allow verifiers to reject a task", async function () {
            const { contract, deadline, taskHash } =  await loadFixture(deploy);

            await contract.createProject(
                "Project 1",
                "Description",
                deadline,
                true,
                [verifier1],
                []
            );

            await contract.connect(student1).submitTask(0, taskHash);

            await expect(contract.connect(verifier1).rejectTask(0, student1.address))
                .to.emit(contract, "TaskRejected")
                .withArgs(0, student1.address);
        });

        it("Should revert non-verifier to verify a task", async function () {
            const { contract, deadline, taskHash } =  await loadFixture(deploy);

            await contract.createProject(
                "Project 1",
                "Description",
                deadline,
                false,
                [verifier1],
                []
            );
            await contract.connect(student1).submitTask(0, taskHash);

            await expect(contract.connect(verifier2).verifyTask(0, student1.address, 90))
                .to.be.revertedWith("Not a verifier");
        });

        it("Should revert non-verifier to reject a task", async function () {
            const { contract, deadline, taskHash } =  await loadFixture(deploy);

            await contract.createProject(
                "Project 1",
                "Description",
                deadline,
                false,
                [verifier1],
                []
            );
            await contract.connect(student1).submitTask(0, taskHash);

            await expect(contract.connect(verifier2).rejectTask(0, student1.address))
                .to.be.revertedWith("Not a verifier");
        });

        it("Should revert verifying/rejecting already verified task", async function () {
            const { contract, deadline, taskHash } =  await loadFixture(deploy);

            await contract.createProject(
                "Project 1",
                "Description",
                deadline,
                true,
                [verifier1],
                []
            );

            await contract.connect(student1).submitTask(0, taskHash)
            await expect(contract.connect(verifier1).verifyTask(0, student1.address, 90))
                .to.emit(contract, "TaskVerified")
                .withArgs(0, student1.address, taskHash, 90);

            await expect(contract.connect(verifier1).verifyTask(0, student1.address, 90))
                .to.be.revertedWith("Task already verified");
            await expect(contract.connect(verifier1).rejectTask(0, student1.address))
                .to.be.revertedWith("Task already verified");
        });

        it("Should revert verifying/rejecting already rejected task", async function () {
            const { contract, deadline, taskHash } =  await loadFixture(deploy);

            await contract.createProject(
                "Project 1",
                "Description",
                deadline,
                true,
                [verifier1],
                []
            );

            await contract.connect(student1).submitTask(0, taskHash)

            await expect(contract.connect(verifier1).rejectTask(0, student1.address))
                .to.emit(contract, "TaskRejected")
                .withArgs(0, student1.address);

            await expect(contract.connect(verifier1).verifyTask(0, student1.address, 90))
                .to.be.revertedWith("Task already rejected");
            await expect(contract.connect(verifier1).rejectTask(0, student1.address))
                .to.be.revertedWith("Task already rejected");
        });
    })
});
