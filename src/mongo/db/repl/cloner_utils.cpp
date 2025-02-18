/**
 *    Copyright (C) 2020-present MongoDB, Inc.
 *
 *    This program is free software: you can redistribute it and/or modify
 *    it under the terms of the Server Side Public License, version 1,
 *    as published by MongoDB, Inc.
 *
 *    This program is distributed in the hope that it will be useful,
 *    but WITHOUT ANY WARRANTY; without even the implied warranty of
 *    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *    Server Side Public License for more details.
 *
 *    You should have received a copy of the Server Side Public License
 *    along with this program. If not, see
 *    <http://www.mongodb.com/licensing/server-side-public-license>.
 *
 *    As a special exception, the copyright holders give permission to link the
 *    code of portions of this program with the OpenSSL library under certain
 *    conditions as described in each individual source file and distribute
 *    linked combinations including the program with the OpenSSL library. You
 *    must comply with the Server Side Public License in all respects for
 *    all of the code used other than as permitted herein. If you modify file(s)
 *    with this exception, you may extend this exception to your version of the
 *    file(s), but you are not obligated to do so. If you do not wish to do so,
 *    delete this exception statement from your version. If you delete this
 *    exception statement from all source files in the program, then also delete
 *    it in the license file.
 */

#include "mongo/platform/basic.h"

#include "mongo/bson/bsonobjbuilder.h"
#include "mongo/db/multitenancy_gen.h"
#include "mongo/db/namespace_string.h"
#include "mongo/db/repl/cloner_utils.h"
#include "mongo/db/repl/read_concern_args.h"

namespace mongo {
namespace repl {

BSONObj ClonerUtils::makeTenantDatabaseRegex(StringData prefix) {
    return BSON("$regex"
                << "^" + prefix + "_");
}

BSONObj ClonerUtils::makeTenantDatabaseFilter(StringData prefix) {
    return BSON("name" << makeTenantDatabaseRegex(prefix));
}

BSONObj ClonerUtils::buildMajorityWaitRequest(Timestamp operationTime) {
    BSONObjBuilder bob;
    bob.append("find", NamespaceString::kSystemReplSetNamespace.toString());
    bob.append("filter", BSONObj());
    ReadConcernArgs readConcern(LogicalTime(operationTime), ReadConcernLevel::kMajorityReadConcern);
    readConcern.appendInfo(&bob);
    return bob.obj();
}

bool ClonerUtils::isDatabaseForTenant(StringData db, StringData prefix) {
    return db.startsWith(prefix + "_");
}

// TODO SERVER-70027: Pass tenantID object to this function instead of StringData.
bool ClonerUtils::isNamespaceForTenant(NamespaceString nss, StringData prefix) {
    if (gMultitenancySupport && nss.tenantId() != boost::none) {
        return nss.tenantId()->toString() == prefix;
    }
    return isDatabaseForTenant(nss.db(), prefix);
}

}  // namespace repl
}  // namespace mongo
