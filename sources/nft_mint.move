module main_addr::nftaptv1{
    use aptos_framework::account;
    use std::string::{Self, String};
    use std::string_utils;
    use std::signer;
    use std::vector;
    use aptos_std::table::{Self, Table};
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    use aptos_token_objects::aptos_token::{Self, AptosToken};
    use aptos_framework::object::{Self, Object, ConstructorRef};
    use aptos_token_objects::royalty;


    struct CollectionData has key {
        collection_name: String,
        collection_description: String,
        baseuri: String,
        royalty_address: address,
        royalty_denominator: u64,
        royalty_numerator: u64,
        presale_mint_time: u64,
        public_sale_mint_time: u64,
        paused: bool,
        total_supply: u64,
        minted: u64,
        mint_limit: u64,
        burnable: bool
    }

    struct MinterList has key {
        minters: Table<address, u64>, //save address of minters + how many they have minted so far
        count: u64
    }

    struct ResourceInfo has key {
        source: address,
        resource_cap: account::SignerCapability
    }

    //errors

    const INDIVIDUAL_MINT_COUNT_EXCEEDED: u64 = 0;
    const MINT_NOT_LIVE: u64 = 1;
    const MINT_PAUSED: u64 = 2;
    const MINT_UNAVAILABLE: u64 = 3;

    public entry fun create_collection_entry(
        creator: &signer, 
        collection_name: String,
        collection_description: String,
        baseuri: String,
        royalty_address: address,
        royalty_denominator: u64,
        royalty_numerator: u64,
        presale_mint_time: u64,
        public_sale_mint_time: u64,
        paused: bool,
        total_supply: u64,
        minted: u64,
        mint_limit: u64,
        burnable: bool,
        seeds: vector<u8> ){
            create_collection(
                creator, 
                collection_name,
                collection_description,
                baseuri,
                royalty_address,
                royalty_denominator,
                royalty_numerator,
                presale_mint_time,
                public_sale_mint_time,
                paused,
                total_supply,
                minted,
                mint_limit,
                burnable,
                seeds);
        }

    public fun create_collection(
        creator: &signer, 
        collection_name: String,
        collection_description: String,
        baseuri: String,
        royalty_address: address,
        royalty_denominator: u64,
        royalty_numerator: u64,
        presale_mint_time: u64,
        public_sale_mint_time: u64,
        paused: bool,
        total_supply: u64,
        minted: u64,
        mint_limit: u64,
        burnable: bool,
        seeds: vector<u8> ): ConstructorRef {

    let constructor_ref = object::create_object_from_account(creator);
    let object_signer = object::generate_signer(&constructor_ref);

    let (_resource, resource_cap) = account::create_resource_account(creator, seeds);
    let resource_signer_from_cap = account::create_signer_with_capability(&resource_cap);
    let resource_account_address = signer::address_of(&resource_signer_from_cap);

    move_to<ResourceInfo>(
            &object_signer,
            ResourceInfo { resource_cap, source: signer::address_of(creator) }
        );

    let collection_id = aptos_token::create_collection_object(
        &resource_signer_from_cap,
            collection_description,
            total_supply,
            collection_name,
            baseuri,
            true,
            true,
            true,
            true,
            true,
            true,
            true,
            true,
            true,
            royalty_numerator,
            royalty_denominator
    );

    let royalty = royalty::create(royalty_numerator, royalty_denominator, royalty_address);
    aptos_token::set_collection_royalties(&resource_signer_from_cap, collection_id, royalty);


    move_to<CollectionData>(&object_signer,
        CollectionData {collection_name,
            collection_description,
            baseuri,
            royalty_address,
            royalty_denominator,
            royalty_numerator,
            presale_mint_time,
            public_sale_mint_time,
            total_supply,
            minted: 0,
            paused,
            mint_limit,
            burnable}
    );

    constructor_ref
    }

    public entry fun mint_token_entry(receiver: &signer, creator_obj:address, token_name: String, token_uri: String, is_sbt: bool, serialize_name: bool) acquires CollectionData, ResourceInfo, MinterList{
        mint_token(receiver, creator_obj, token_name, token_uri, is_sbt, serialize_name);
    }
   
    
    public fun mint_token(receiver: &signer, creator_obj:address, token_name: String, token_uri: String, is_sbt: bool, serialize_name: bool): Object<AptosToken> acquires CollectionData, ResourceInfo, MinterList{

            let resource_data = borrow_global<ResourceInfo>(creator_obj);
            let receiver_addr = signer::address_of(receiver);
            let creator = resource_data.source;
            let resource_signer_from_cap = account::create_signer_with_capability(&resource_data.resource_cap);

            let collection_data = borrow_global_mut<CollectionData>(creator_obj);
            let minter_list = borrow_global_mut<MinterList>(creator_obj);

            let now = aptos_framework::timestamp::now_seconds();
            //check if mint during given timeperiod

            assert!(now >= collection_data.public_sale_mint_time, MINT_NOT_LIVE); 

            //check if paused
            assert!(!collection_data.paused, MINT_PAUSED);

            //check if total supply minted
            assert!(collection_data.minted != collection_data.total_supply, MINT_UNAVAILABLE);    
            

            if(table::contains(&minter_list.minters, receiver_addr)){
                let minter_nft_count = table::borrow(&minter_list.minters, receiver_addr);
                
                assert!(*minter_nft_count < collection_data.mint_limit, INDIVIDUAL_MINT_COUNT_EXCEEDED);
            };

            let royalty = royalty::create(collection_data.royalty_numerator, collection_data.royalty_denominator, collection_data.royalty_address);
            let minted_token;
            if(is_sbt == false){
                let coll_name = token_name;
                if(serialize_name == true){
                    coll_name = collection_data.collection_name;
                    string::append(&mut coll_name, string::utf8(b" #"));
                    let string_minted_num = string_utils::format1(&b"{}", collection_data.minted);
                    string::append(&mut coll_name, string_minted_num);
                };
                
                minted_token = aptos_token::mint_token_object(
                    &resource_signer_from_cap,
                    collection_data.collection_name,
                    collection_data.collection_description,
                    coll_name,
                    token_uri,
                    vector::empty<String>(),
                    vector::empty<String>(),
                    vector::empty()
                );

                object::transfer(&resource_signer_from_cap, minted_token, receiver_addr);

            }
            else{
                minted_token = aptos_token::mint_soul_bound_token_object(
                &resource_signer_from_cap,
                collection_data.collection_name,
                collection_data.collection_description,
                token_name,
                token_uri,
                vector::empty<String>(),
                vector::empty<String>(),
                vector::empty(),
                receiver_addr
            );

            };

            collection_data.minted = collection_data.minted + 1;
            if(!table::contains(&minter_list.minters, receiver_addr)){
                table::upsert(&mut minter_list.minters, receiver_addr, 1);
            }
            else    {
            let minter_nft_count = table::borrow_mut(&mut minter_list.minters, receiver_addr);
            *minter_nft_count = *minter_nft_count + 1 
            };

            minted_token
            
    }

}