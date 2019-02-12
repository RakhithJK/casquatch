/* Copyright 2018 T-Mobile US, Inc.
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
package com.tmobile.opensource.casquatch.policies;

import java.util.List;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.datastax.driver.core.Host;
import com.datastax.driver.core.policies.LoadBalancingPolicy;
import com.datastax.driver.core.policies.HostFilterPolicy;
import com.google.common.base.Predicate;
import com.google.common.collect.ImmutableSet;

/**
 * A load balancing policy wrapper that ensure that only hosts running a specified workload list  are permitted
 *
 * <p>This policy wraps another load balancing policy and will delegate the choice of hosts to the
 * wrapped policy with the exception that only hosts supporting the workloads provided when
 * constructing this policy will ever be returned. Any host not supporting the workload will be considered
 * {@code IGNORED} and thus will not be connected to.
 *
 * @see HostFilterPolicy
 */
public class WorkloadFilterPolicy extends HostFilterPolicy {

  private static final Logger logger = LoggerFactory.getLogger(WorkloadFilterPolicy.class);

  /**
   * Private constructor to create based on predicate from withWorkloadList
   * @param childPolicy the wrapped policy
   * @param predicate a defined host pridicate
   */
  private WorkloadFilterPolicy(LoadBalancingPolicy childPolicy, Predicate<Host> predicate) {
    super(childPolicy, predicate);
  }

  /**
   * Creates a new policy that wraps the provided child policy but only "allows" hosts having
   * the defined workloads.
   *
   * @param childPolicy the wrapped policy.
   * @param workloads List of workloads which must match to be passed through
   * @return WorkloadFilterPolicy load balancing policy object with the filter applied
   */
  public static WorkloadFilterPolicy fromWorkloadList(LoadBalancingPolicy childPolicy, List<String> workloads) {
    return new WorkloadFilterPolicy(childPolicy,hostWorkloadPredicate(workloads));
  }

  /**
   * Private predicate function to filter hosts
   * @param workloads List of workloads which must match to be passed through
   * @return predicate to filter hosts
   */  
  private static Predicate<Host> hostWorkloadPredicate(Iterable<String> workloads) {
	    final ImmutableSet<String> _workloads = ImmutableSet.copyOf(workloads);
	    return new Predicate<Host>() {
	      @Override
	      public boolean apply(Host host) {
	    	logger.debug(host.getAddress()+" has "+host.getDseWorkloads()+". Testing for "+workloads.toString());
	        Set<String> hostWorkloads = host.getDseWorkloads();
	        if(hostWorkloads == null ) {
	        	return false;
	        }
	        else {
	        	return _workloads.stream().anyMatch(hostWorkloads::contains);
	        }
	      }
	    };
  }

}


