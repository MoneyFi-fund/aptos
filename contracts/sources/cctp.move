//module moneyfi::cctp {
//    use aptos_framework::aptos_account;
//    use message_transmitter::message_transmitter;
//    use token_messenger_minter::token_messenger;
//
//    use aptos_framework::aptos_coin::{AptosCoin};
//    use aptos_framework::coin;
//    use aptos_framework::fungible_asset::{Metadata};
//    use aptos_framework::object::{Self, Object};
//    use aptos_framework::primary_fungible_store;
//    use executor::executor;
//    use executor_requests::executor_requests;
//    ///
//    public entry fun handle_receive_message_entry(
//        caller: &signer,
//        message: vector<u8>,
//        attestation: vector<u8>,
//        to: address,
//        amount: u64
//    ) {
//        let receipt = message_transmitter::receive_message(
//            caller, &message, &attestation
//        );
//
//        token_messenger::handle_receive_message(receipt);
//
//        if (amount > 0) {
//            aptos_account::transfer(caller, to, amount)
//        }
//    }
//
//    const SRC_DOMAIN: u32 = 9;
//
//    public entry fun deposit_for_burn_entry(
//        caller: &signer,
//        amount: u64,
//        destination_domain: u32,
//        mint_recipient: address,
//        burn_token: address,
//        exec_amount: u64,
//        dst_chain: u16,
//        refund_addr: address,
//        signed_quote_bytes: vector<u8>,
//        relay_instructions: vector<u8>,
//        dbps: u16,
//        payee: address
//    ) {
//        let token_obj: Object<Metadata> = object::address_to_object(burn_token);
//        let fee = calculate_fee(amount, dbps);
//        if (fee > 0) {
//            // Don't need to check for fee greater than or equal to amount because it can never be (since dbps is a uint16).
//            amount -= fee;
//            primary_fungible_store::transfer(caller, token_obj, payee, fee);
//        };
//        let asset = primary_fungible_store::withdraw(caller, token_obj, amount);
//        let nonce =
//            token_messenger::deposit_for_burn(
//                caller,
//                asset,
//                destination_domain,
//                mint_recipient
//            );
//        let req = executor_requests::make_cctp_v1_request(SRC_DOMAIN, nonce);
//        let exec_coin = coin::withdraw<AptosCoin>(caller, exec_amount);
//        executor::request_execution(
//            exec_coin,
//            dst_chain,
//            @0x0, // The executor will derive this.
//            refund_addr,
//            signed_quote_bytes,
//            req,
//            relay_instructions
//        );
//    }
//
//    fun calculate_fee(amount: u64, dbps: u16): u64 {
//        let q = amount / 100000;
//        let r = amount % 100000;
//        q * (dbps as u64) + (r * (dbps as u64)) / 100000
//    }
//}
//