
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract FreelanceEscrow {

    address public immutable arbiter;
    uint256 public jobCount;
    bool private locked;

    enum Status {
        Created,
        Funded,
        Submitted,
        Disputed,
        Released,
        Refunded
    }

    struct Job {
        uint256 jobId;
        address employer;
        address freelancer;
        string title;
        string description;
        uint256 amount;
        uint256 deadline;
        string workEvidence;
        string disputeReason;
        Status status;
    }

    mapping(uint256 => Job) private jobs;

    // Events
    event JobCreated(
        uint256 indexed jobId,
        address indexed employer,
        address indexed freelancer,
        uint256 amount
    );

    event PaymentDeposited(
        uint256 indexed jobId,
        address employer,
        uint256 amount
    );

    event WorkSubmitted(
        uint256 indexed jobId,
        string evidence
    );

    event PaymentReleased(
        uint256 indexed jobId,
        address freelancer,
        uint256 amount
    );

    event DisputeRaised(
        uint256 indexed jobId,
        address raisedBy,
        string reason
    );

    event DisputeResolved(
        uint256 indexed jobId,
        bool paidToFreelancer
    );

    // Modifiers
    modifier onlyArbiter() {
        require(msg.sender == arbiter, "Only arbiter");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    // Constructor
    constructor() {
        arbiter = msg.sender;
    }

    // 1. Create Job
    function createJob(
        address _freelancer,
        string memory _title,
        string memory _description,
        uint256 _amount,
        uint256 _deadline
    ) external returns (uint256) {

        require(_freelancer != address(0), "Invalid freelancer");
        require(_freelancer != msg.sender, "Cannot hire yourself");
        require(_amount > 0, "Amount must be greater than zero");
        require(_deadline > block.timestamp, "Invalid deadline");

        uint256 id = jobCount;

        jobs[id] = Job({
            jobId: id,
            employer: msg.sender,
            freelancer: _freelancer,
            title: _title,
            description: _description,
            amount: _amount,
            deadline: _deadline,
            workEvidence: "",
            disputeReason: "",
            status: Status.Created
        });

        jobCount++;

        emit JobCreated(
            id,
            msg.sender,
            _freelancer,
            _amount
        );

        return id;
    }

    // 2. Deposit Payment
    function depositPayment(uint256 _jobId)
        external
        payable
    {
        require(_jobId < jobCount, "Job does not exist");

        Job storage j = jobs[_jobId];

        require(msg.sender == j.employer, "Only employer");
        require(j.status == Status.Created, "Invalid job status");
        require(msg.value == j.amount, "Incorrect ETH amount");

        j.status = Status.Funded;

        emit PaymentDeposited(
            _jobId,
            msg.sender,
            msg.value
        );
    }

    // 3. Submit Work
    function submitWork(
        uint256 _jobId,
        string memory _evidence
    ) external {

        require(_jobId < jobCount, "Job does not exist");

        Job storage j = jobs[_jobId];

        require(msg.sender == j.freelancer, "Only freelancer");
        require(j.status == Status.Funded, "Job not funded");
        require(block.timestamp <= j.deadline, "Deadline passed");
        require(bytes(_evidence).length > 0, "Evidence required");

        j.workEvidence = _evidence;
        j.status = Status.Submitted;

        emit WorkSubmitted(_jobId, _evidence);
    }

    // 4. Approve & Release Payment
    function approveAndRelease(uint256 _jobId)
        external
        nonReentrant
    {
        require(_jobId < jobCount, "Job does not exist");

        Job storage j = jobs[_jobId];

        require(msg.sender == j.employer, "Only employer");
        require(j.status == Status.Submitted, "Work not submitted");

        uint256 payment = j.amount;
        address payable recipient = payable(j.freelancer);

        j.status = Status.Released;

        (bool success, ) = recipient.call{value: payment}("");

        require(success, "Payment transfer failed");

        emit PaymentReleased(
            _jobId,
            recipient,
            payment
        );
    }

    // 5. Dispute Management
    function raiseDispute(
        uint256 _jobId,
        string memory _reason
    ) external {

        require(_jobId < jobCount, "Job does not exist");

        Job storage j = jobs[_jobId];

        require(
            msg.sender == j.employer ||
            msg.sender == j.freelancer,
            "Not authorized"
        );

        require(
            j.status == Status.Funded ||
            j.status == Status.Submitted,
            "Cannot dispute this job"
        );

        require(bytes(_reason).length > 0, "Reason required");

        j.disputeReason = _reason;
        j.status = Status.Disputed;

        emit DisputeRaised(
            _jobId,
            msg.sender,
            _reason
        );
    }

    // Arbiter resolves dispute
    function resolveDispute(
        uint256 _jobId,
        bool _payFreelancer
    ) external onlyArbiter nonReentrant {

        require(_jobId < jobCount, "Job does not exist");

        Job storage j = jobs[_jobId];

        require(j.status == Status.Disputed, "No active dispute");

        uint256 payment = j.amount;

        if (_payFreelancer) {

            j.status = Status.Released;

            (bool success, ) =
                payable(j.freelancer).call{value: payment}("");

            require(success, "Payment failed");

            emit PaymentReleased(
                _jobId,
                j.freelancer,
                payment
            );

        } else {

            j.status = Status.Refunded;

            (bool success, ) =
                payable(j.employer).call{value: payment}("");

            require(success, "Refund failed");
        }

        emit DisputeResolved(
            _jobId,
            _payFreelancer
        );
    }

    // 6. Transaction Tracking

    function getJob(uint256 _jobId)
        external
        view
        returns (Job memory)
    {
        require(_jobId < jobCount, "Job does not exist");

        return jobs[_jobId];
    }

    function getJobCount()
        external
        view
        returns (uint256)
    {
        return jobCount;
    }

    function getEscrowBalance()
        external
        view
        returns (uint256)
    {
        return address(this).balance;
    }

    function getStatus(uint256 _jobId)
        external
        view
        returns (Status)
    {
        require(_jobId < jobCount, "Job does not exist");

        return jobs[_jobId].status;
    }
}
