/*-------------------------------------------------------------------------------
This file is part of Ranger.
    
Ranger is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Ranger is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Ranger. If not, see <http://www.gnu.org/licenses/>.

Written by: 

Marvin N. Wright
Institut für Medizinische Biometrie und Statistik
Universität zu Lübeck
Ratzeburger Allee 160
23562 Lübeck 

http://www.imbs-luebeck.de
wright@imbs.uni-luebeck.de
#-------------------------------------------------------------------------------*/

#ifndef TREECLASSIFICATION_H_
#define TREECLASSIFICATION_H_

#include "globals.h"
#include "Tree.h"

class TreeClassification: public Tree {
public:
  TreeClassification(std::vector<double>* class_values, std::vector<uint>* response_classIDs);

  // Create from loaded forest
  TreeClassification(std::vector<std::vector<size_t>>& child_nodeIDs, std::vector<size_t>& split_varIDs,
      std::vector<double>& split_values, std::vector<double>* class_values, std::vector<uint>* response_classIDs);

  virtual ~TreeClassification();

  void addPrediction(size_t nodeID, size_t sampleID);
  double estimate(size_t nodeID);
  void computePermutationImportanceInternal(std::vector<std::vector<size_t>>* permutations);
  void appendToFileInternal(std::ofstream& file);

private:
  bool splitNodeInternal(size_t nodeID, std::unordered_set<size_t>& possible_split_varIDs);
  void createEmptyNodeInternal();

  double computePredictionAccuracyInternal();

  // Called by splitNodeInternal(). Sets split_varIDs and split_values.
  bool findBestSplit(size_t nodeID, std::unordered_set<size_t>& possible_split_varIDs);

  void addGiniImportance(size_t nodeID, size_t varID, double decrease);

  void reservePredictionMemory(size_t num_predictions) {
    predictions.push_back(std::vector<double>());
    predictions[0].resize(num_predictions, 0);
  }

  // Classes of the dependent variable and classIDs for responses
  std::vector<double>* class_values;
  std::vector<uint>* response_classIDs;

  DISALLOW_COPY_AND_ASSIGN(TreeClassification);
};

#endif /* TREECLASSIFICATION_H_ */