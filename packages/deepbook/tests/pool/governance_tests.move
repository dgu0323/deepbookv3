#[test_only]
module deepbook::governance_tests {
    use sui::test_scenario::{Self as test, Scenario, next_tx, end};
    use deepbook::governance;

    const ALICE: address = @0xA;
    const BOB: address = @0xB;

    #[test]
    fun new_proposal() {
        let (mut scenario, owner) = setup();
        next_tx(&mut scenario, owner);
        let mut metadata = governance::empty(0);
        metadata.adjust_voting_power(0, 300000);
        metadata.refresh(1); // quorum = 150
        metadata.add_proposal(500000, 200000, 10000, 1000, owner);

        // Alice votes with 100 stake, not enough to push owner proposal over quorum
        let winning_proposal = metadata.vote(option::none(), option::some(owner), 100);
        assert!(winning_proposal.is_none(), 0);

        // Bob votes with 200000 stake, enough to push owner proposal over quorum
        let winning_proposal = metadata.vote(option::none(), option::some(owner), 200000);
        let (taker_fee, maker_fee, stake_required) = winning_proposal.borrow().params();
        assert!(maker_fee == 200000, 0);
        assert!(taker_fee == 500000, 0);
        assert!(stake_required == 10000, 0);

        metadata.add_proposal(600000, 300000, 20000, 1000, ALICE);

        // Alice moves 100 stake from owner proposal to Alice proposal, but not enough to push Alice proposal over quorum
        let winning_proposal = metadata.vote(option::some(owner), option::some(ALICE), 100);
        let (taker_fee, maker_fee, stake_required) = winning_proposal.borrow().params();
        assert!(maker_fee == 200000, 0);
        assert!(taker_fee == 500000, 0);
        assert!(stake_required == 10000, 0);

        // Bob removes 200000 votes from owner proposal, no proposal is over quorum
        let winning_proposal = metadata.vote(option::some(owner), option::none(), 200000);
        assert!(winning_proposal.is_none(), 0);

        // Bob voting on Alice proposal is enough to get it over quorum
        let winning_proposal = metadata.vote(option::none(), option::some(ALICE), 200000);
        let (taker_fee, maker_fee, stake_required) = winning_proposal.borrow().params();
        assert!(maker_fee == 300000, 0);
        assert!(taker_fee == 600000, 0);
        assert!(stake_required == 20000, 0);

        metadata.delete();
        end(scenario);
    }

    #[test]
    fun new_proposal_stable() {
        let (mut scenario, owner) = setup();
        next_tx(&mut scenario, owner);
        let mut metadata = governance::empty(0);
        metadata.set_as_stable(true);

        metadata.add_proposal(50000, 20000, 10000, 1000, owner);
        metadata.add_proposal(100000, 50000, 20000, 1000, ALICE);

        assert!(metadata.proposals().size() == 2, 0);
        metadata.delete();
        end(scenario);
    }

    #[test]
    fun change_vote_from_deleted() {
        let (mut scenario, owner) = setup();
        next_tx(&mut scenario, owner);
        let mut metadata = governance::empty(0);
        metadata.add_proposal(600000, 300000, 20000, 1000, ALICE);

        metadata.vote(option::some(owner), option::some(ALICE), 100);
        metadata.delete();
        end(scenario);
    }

    #[test, expected_failure(abort_code = governance::EAlreadyProposed)]
    fun repeat_proposer_e() {
        let (mut scenario, owner) = setup();
        next_tx(&mut scenario, owner);
        let mut metadata = governance::empty(0);
        metadata.set_as_stable(true);

        metadata.add_proposal(50000, 20000, 10000, 1000, owner);
        metadata.add_proposal(100000, 50000, 20000, 1000, owner);

        assert!(metadata.proposals().size() == 2, 0);
        metadata.delete();
        end(scenario);
    }

    #[test]
    fun voting_power() {
        let (mut scenario, owner) = setup();
        next_tx(&mut scenario, owner);
        {
            // New gov has 0 for all values
            let mut metadata = governance::empty(0);
            assert!(metadata.voting_power() == 0, 0);
            assert!(metadata.quorum() == 0, 0);
            assert!(metadata.proposals().size() == 0, 0);

            // Increase voting power by 300 stake, but quorum isn't increased until next epoch reset
            metadata.adjust_voting_power(0, 300);
            assert!(metadata.voting_power() == 300, 0);
            assert!(metadata.quorum() == 0, 0);

            // Resetting the epoch sets quorum to 150
            metadata.refresh(1);
            assert!(metadata.quorum() == 150, 0);

            // Alice creates a new proposal and votes on it
            metadata.add_proposal(500000, 200000, 10000, 1000, ALICE);
            metadata.vote(option::none(), option::some(ALICE), 100);
            assert!(metadata.proposals().size() == 1, 0);
            assert!(metadata.proposal_votes(ALICE) == 100, 0);

            // Bob votes on Alice's proposal
            metadata.vote(option::none(), option::some(ALICE), 200);
            assert!(metadata.proposal_votes(ALICE) == 300, 0);

            // Alice removes vote from her own proposal
            metadata.vote(option::some(ALICE), option::none(), 100);
            assert!(metadata.proposal_votes(ALICE) == 200, 0);

            // New proposal, proposals = 2
            metadata.add_proposal(600000, 300000, 20000, 1000, owner);
            assert!(metadata.proposals().size() == 2, 0);

            // Decrease voting power, but quorum isn't decreased until next epoch reset
            metadata.adjust_voting_power(100, 0);
            assert!(metadata.voting_power() == 200, 0);
            assert!(metadata.quorum() == 150, 0);

            // Reset to get rid of all proposals and voters. Quorum updated
            metadata.refresh(2);
            assert!(metadata.voting_power() == 200, 0);
            assert!(metadata.quorum() == 100, 0);
            assert!(metadata.proposals().size() == 0, 0);

            // Stake of 2000, over threshold of 1000, gain 1500 voting power
            metadata.adjust_voting_power(0, 2000);
            assert!(metadata.voting_power() == 1700, 0);
            // Any more additions by this user increases voting power by half
            metadata.adjust_voting_power(2000, 3000);
            assert!(metadata.voting_power() == 2200, 0);
            // Stake added by someone else still counts as full voting power
            metadata.adjust_voting_power(0, 300);
            assert!(metadata.voting_power() == 2500, 0);
            // Whale removes his 3000 stake, reducing voting power by 2000
            metadata.adjust_voting_power(3000, 0);
            assert!(metadata.voting_power() == 500, 0);

            metadata.delete();
        };

        end(scenario);
    }

    #[test, expected_failure(abort_code = governance::EProposalDoesNotExist)]
    fun proposal_does_not_exist_e() {
        let (mut scenario, owner) = setup();
        next_tx(&mut scenario, owner);
        {
            let mut metadata = governance::empty(0);
            metadata.add_proposal(500000, 200000, 10000, 1000, owner);
            metadata.vote(option::none(), option::some(BOB), 100);
            abort 0
        }
    }

    #[test, expected_failure(abort_code = governance::EInvalidTakerFee)]
    fun new_proposal_taker_too_high_e() {
        let (mut scenario, owner) = setup();
        next_tx(&mut scenario, owner);
        {
            let mut metadata = governance::empty(0);
            metadata.add_proposal(1001000, 200000, 10000, 1000, owner);
            abort 0
        }
    }

    #[test, expected_failure(abort_code = governance::EInvalidTakerFee)]
    fun new_proposal_taker_too_low_e() {
        let (mut scenario, owner) = setup();
        next_tx(&mut scenario, owner);
        {
            let mut metadata = governance::empty(0);
            metadata.add_proposal(499000, 200000, 10000, 1000, owner);
            abort 0
        }
    }

    #[test, expected_failure(abort_code = governance::EInvalidTakerFee)]
    fun new_proposal_taker_too_high_stable_e() {
        let (mut scenario, owner) = setup();
        next_tx(&mut scenario, owner);
        {
            let mut metadata = governance::empty(0);
            metadata.set_as_stable(true);
            metadata.add_proposal(200000, 50000, 10000, 1000, owner);
            abort 0
        }
    }

    #[test, expected_failure(abort_code = governance::EInvalidMakerFee)]
    fun new_proposal_maker_too_high_e() {
        let (mut scenario, owner) = setup();
        next_tx(&mut scenario, owner);
        {
            let mut metadata = governance::empty(0);
            metadata.add_proposal(500000, 501000, 10000, 1000, owner);
            abort 0
        }
    }

    #[test, expected_failure(abort_code = governance::EInvalidMakerFee)]
    fun new_proposal_maker_too_low_e() {
        let (mut scenario, owner) = setup();
        next_tx(&mut scenario, owner);
        {
            let mut metadata = governance::empty(0);
            metadata.add_proposal(500000, 199000, 10000, 1000, owner);
            abort 0
        }
    }

    #[test, expected_failure(abort_code = governance::EInvalidMakerFee)]
    fun new_proposal_maker_too_high_stable_e() {
        let (mut scenario, owner) = setup();
        next_tx(&mut scenario, owner);
        {
            let mut metadata = governance::empty(0);
            metadata.set_as_stable(true);
            metadata.add_proposal(100000, 100000, 10000, 1000, owner);
            abort 0
        }
    }

    fun setup(): (Scenario, address) {
        let scenario = test::begin(@0x1);
        let owner = @0xF;

        (scenario, owner)
    }
}
