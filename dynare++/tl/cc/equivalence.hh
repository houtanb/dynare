// Copyright 2004, Ondra Kamenik

// Equivalences.

/* Here we define an equivalence of a set of integers $\{0, 1, \ldots,
   k-1\}$. The purpose is clear, in the tensor library we often iterate
   through all equivalences and sum matrices. We need an abstraction for
   an equivalence class, equivalence and a set of all equivalences.

   The equivalence class (which is basically a set of integers) is here
   implemented as ordered integer sequence. The ordered sequence is not
   implemented via |IntSequence|, but via |vector<int>| since we need
   insertions. The equivalence is implemented as an ordered list of
   equivalence classes, and equivalence set is a list of equivalences.

   The ordering of the equivalence classes within an equivalence is very
   important. For instance, if we iterate through equivalences for $k=5$
   and pickup some equivalence class, say $\{\{0,4\},\{1,2\},\{3\}\}$, we
   then evaluate something like:
   $$\left[B_{y^2u^3}\right]_{\alpha_1\alpha_2\beta_1\beta_2\beta_3}=
   \cdots+\left[g_{y^3}\right]_{\gamma_1\gamma_2\gamma_3}
   \left[g_{yu}\right]^{\gamma_1}_{\alpha_1\beta_3}
   \left[g_{yu}\right]^{\gamma_2}_{\alpha_2\beta_1}
   \left[g_u\right]^{\gamma_3}_{\beta_2}+\cdots
   $$
   If the tensors are unfolded, we can evaluate this expression as
   $$g_{y^3}\cdot\left(g_{yu}\otimes g_{yu}\otimes g_{u}\right)\cdot P,$$
   where $P$ is a suitable permutation of columns of the expressions,
   which permutes them so that the index
   $(\alpha_1,\beta_3,\alpha_2,\beta_1,\beta_2)$ would go to
   $(\alpha_1,\alpha_2,\beta_1,\beta_2,\beta_3)$.
   The permutation $P$ can be very ineffective (copying great amount of
   small chunks of data) if the equivalence class ordering is chosen
   badly. However, we do not provide any heuristic minimizing a total
   time spent in all permutations. We choose an ordering which orders the
   classes according to their averages, and according to the smallest
   equivalence class element if the averages are the same. */

#ifndef EQUIVALENCE_H
#define EQUIVALENCE_H

#include "int_sequence.hh"

#include <vector>
#include <list>

using namespace std;

/* Here is the abstraction for an equivalence class. We implement it as
   |vector<int>|. We have a constructor for empty class, copy
   constructor. What is important here is the ordering operator
   |operator<| and methods for addition of an integer, and addition of
   another sequence. Also we provide method |has| which returns true if a
   given integer is contained. */

class OrdSequence
{
  vector<int> data;
public:
  OrdSequence() : data()
  {
  }
  OrdSequence(const OrdSequence &s)  
  = default;
  OrdSequence &
  operator=(const OrdSequence &s)
  = default;
  bool operator==(const OrdSequence &s) const;
  int operator[](int i) const;
  bool operator<(const OrdSequence &s) const;
  const vector<int> &
  getData() const
  {
    return data;
  }
  int
  length() const
  {
    return data.size();
  }
  void add(int i);
  void add(const OrdSequence &s);
  bool has(int i) const;
  void print(const char *prefix) const;
private:
  double average() const;
};

/* Here is the abstraction for the equivalence. It is a list of
   equivalence classes. Also we remember |n|, which is a size of
   underlying set $\{0, 1, \ldots, n-1\}$.

   Method |trace| ``prints'' the equivalence into the integer sequence. */

class Permutation;
class Equivalence
{
private:
  int n;
  list<OrdSequence> classes;
public:
  using const_seqit = list<OrdSequence>::const_iterator;
  using seqit = list<OrdSequence>::iterator;

  /* The first constructor constructs $\{\{0\},\{1\},\ldots,\{n-1\}\}$.

     The second constructor constructs $\{\{0,1,\ldots,n-1\}\}$.

     The third is the copy constructor. And the fourth is the copy
     constructor plus gluing |i1| and |i2| in one class. */
  Equivalence(int num);
  Equivalence(int num, const char *dummy);
  Equivalence(const Equivalence &e);
  Equivalence(const Equivalence &e, int i1, int i2);

  const Equivalence &operator=(const Equivalence &e);
  bool operator==(const Equivalence &e) const;
  bool
  operator!=(const Equivalence &e) const
  {
    return !operator==(e);
  }
  int
  getN() const
  {
    return n;
  }
  int
  numClasses() const
  {
    return classes.size();
  }
  void trace(IntSequence &out, int n) const;
  void
  trace(IntSequence &out) const
  {
    trace(out, numClasses());
  }
  void trace(IntSequence &out, const Permutation &per) const;
  void print(const char *prefix) const;
  seqit
  begin()
  {
    return classes.begin();
  }
  const_seqit
  begin() const
  {
    return classes.begin();
  }
  seqit
  end()
  {
    return classes.end();
  }
  const_seqit
  end() const
  {
    return classes.end();
  }
  const_seqit find(int i) const;
  seqit find(int i);
protected:
  /* Here we have find methods. We can find an equivalence class having a
     given number or we can find an equivalence class of a given index within
     the ordering.

     We have also an |insert| method which inserts a given class
     according to the class ordering. */
  const_seqit findHaving(int i) const;
  seqit findHaving(int i);
  void insert(const OrdSequence &s);

};

/* The |EquivalenceSet| is a list of equivalences. The unique
   constructor constructs a set of all equivalences over $n$-element
   set. The equivalences are sorted in the list so that equivalences with
   fewer number of classes are in the end.

   The two methods |has| and |addParents| are useful in the constructor. */

class EquivalenceSet
{
  int n;
  list<Equivalence> equis;
public:
  using const_iterator = list<Equivalence>::const_iterator;
  EquivalenceSet(int num);
  void print(const char *prefix) const;
  const_iterator
  begin() const
  {
    return equis.begin();
  }
  const_iterator
  end() const
  {
    return equis.end();
  }
private:
  bool has(const Equivalence &e) const;
  void addParents(const Equivalence &e, list<Equivalence> &added);
};

/* The equivalence bundle class only encapsulates |EquivalenceSet|s
   from 1 up to a given number. It is able to retrieve the equivalence set
   over $n$-element set for a given $n$, and also it can generate some more
   sets on request.

   It is fully responsible for storage needed for |EquivalenceSet|s. */

class EquivalenceBundle
{
  vector<EquivalenceSet *> bundle;
public:
  EquivalenceBundle(int nmax);
  ~EquivalenceBundle();
  const EquivalenceSet&get(int n) const;
  void generateUpTo(int nmax);
};

#endif
