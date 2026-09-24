package com.eroute.auth;

import java.util.UUID;
import com.eroute.auth.AuthData.Verified;

/** Only external identity verification belongs here. Never accounts, roles or sessions. */
public interface PhoneIdentityVerificationProvider {
 String name();
 String start(UUID transactionId,String phone);
 Verified verifyResult(UUID transactionId,String providerReference,String phone,String evidence);
}
