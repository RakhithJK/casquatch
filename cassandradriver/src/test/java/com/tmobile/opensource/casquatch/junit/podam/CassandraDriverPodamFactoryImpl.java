/*
 * Copyright 2018 T-Mobile US, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.tmobile.opensource.casquatch.junit.podam;

import uk.co.jemos.podam.api.PodamFactoryImpl;

import java.math.BigDecimal;
import java.nio.ByteBuffer;
import java.util.UUID;

public class CassandraDriverPodamFactoryImpl extends PodamFactoryImpl {
    public CassandraDriverPodamFactoryImpl() {
        super();
        this.getStrategy().addOrReplaceTypeManufacturer(UUID.class, new UUIDStrategy());
        this.getStrategy().addOrReplaceTypeManufacturer(ByteBuffer.class, new ByteBufferStrategy());
        this.getStrategy().addOrReplaceTypeManufacturer(BigDecimal.class, new BigDecimalStrategy());
    }
}
