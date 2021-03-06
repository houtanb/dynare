// Copyright 2004, Ondra Kamenik

// Simple threads.

/* This file defines types making a simple interface to
   multi-threading. It follows the classical C++ idioms for traits. We
   have three sorts of traits. The first is a |thread_traits|, which make
   interface to thread functions (run, exit, create and join), the second
   is |mutex_traits|, which make interface to mutexes (create, lock,
   unlock), and third is |cond_traits|, which make interface to
   conditions (create, wait, broadcast, and destroy). At present, there
   are two implementations. The first are POSIX threads, mutexes, and
   conditions, the second is serial (no parallelization).

   The file provides the following interfaces templated by the types
   implementing the threading (like types |pthread_t|, and |pthread_mutex_t|
   for POSIX thread and mutex):
   \unorderedlist
   \li |thread| is a pure virtual class, which must be inherited and a
   method |operator()()| be implemented as the running code of the
   thread. This code is run as a new thread by calling |run| method.
   \li |thread_group| allows insertion of |thread|s and running all of
   them simultaneously joining them. The number of maximum parallel
   threads can be controlled. See below.
   \li |synchro| object locks a piece of code to be executed only serially
   for a given data and specified entry-point. It locks the code until it
   is destructed. So, the typical use is to create the |synchro| object
   on the stack of a function which is to be synchronized. The
   synchronization can be subjected to specific data (then a pointer can
   be passed to |synchro|'s constructor), and can be subjected to
   specific entry-point (then |const char*| is passed to the
   constructor).
   \li |detach_thread| inherits from |thread| and models a detached
   thread in contrast to |thread| which models the joinable thread.
   \li |detach_thread_group| groups the detached threads and runs them. They
   are not joined, they are synchronized by means of a counter counting
   running threads. A change of the counter is checked by waiting on an
   associated condition.
   \endunorderedlist

   What implementation is selected is governed (at present) by
   |HAVE_PTHREAD|. If it is defined, then POSIX threads are linked. If
   it is not defined, then serial implementation is taken. In accordance
   with this, the header file defines macros |THREAD|, |THREAD_GROUP|,
   and |SYNCHRO| as the picked specialization of |thread| (or |detach_thread|),
   |thread_group| (or |detach_thread_group|), and |synchro|.

   The type of implementation is controlled by |thread_impl| integer
   template parameter, this can be |posix| or |empty|.

   The number of maximum parallel threads is controlled via a static
   member of |thread_group| and |detach_thread_group| classes. */

#ifndef STHREAD_H
#define STHREAD_H

#ifdef HAVE_PTHREAD
# include <pthread.h>
#else
/* Give valid types for POSIX thread types, otherwise the templates fail in empty mode.
   Don't use typedefs because on some systems |pthread_t| and friends are typedefs even
   without the include. */
# define pthread_t void *
# define pthread_mutex_t void *
# define pthread_cond_t void *
#endif

#include <cstdio>
#include <list>
#include <map>
#include <type_traits>
#include <memory>
#include <utility>

namespace sthread
{
  using namespace std;

  class Empty
  {
  };

  enum { posix, empty};

  template <int thread_impl>
  class thread;
  template <int>
  class detach_thread;

  /* Clear. We have only |run|, |detach_run|, |exit| and |join|, since
     this is only a simple interface. */

  template <int thread_impl>
  struct thread_traits
  {
    using _Tthread = std::conditional_t<thread_impl == posix, pthread_t, Empty>;
    using _Ctype = thread<0>;
    using _Dtype = detach_thread<0>;
    static void run(_Ctype *c);
    static void detach_run(_Dtype *c);
    static void exit();
    static void join(_Ctype *c);
  };

  /* The class of |thread| is clear. The user implements |operator()()|,
     the method |run| runs the user's code as joinable thread, |exit| kills the
     execution. */
  template <int thread_impl>
  class thread
  {
    using _Ttraits = thread_traits<0>;
    using _Tthread = typename _Ttraits::_Tthread;
    _Tthread th;
  public:
    virtual ~thread()
    = default;
    _Tthread &
    getThreadIden()
    {
      return th;
    }
    const _Tthread &
    getThreadIden() const
    {
      return th;
    }
    virtual void operator()() = 0;
    void
    run()
    {
      _Ttraits::run(this);
    }
    void
    detach_run()
    {
      _Ttraits::detach_run(this);
    }
    void
    exit()
    {
      _Ttraits::exit();
    }
  };

  /* The |thread_group| is also clear. We allow a user to insert the
     |thread|s, and then launch |run|, which will run all the threads not
     allowing more than |max_parallel_threads| joining them at the
     end. This static member can be set from outside. */

  template <int thread_impl>
  class thread_group
  {
    using _Ttraits = thread_traits<thread_impl>;
    using _Ctype = thread<thread_impl>;
    list<_Ctype *> tlist;
    using iterator = typename list<_Ctype *>::iterator;
  public:
    static int max_parallel_threads;
    void
    insert(_Ctype *c)
    {
      tlist.push_back(c);
    }
    /* The thread group class maintains list of pointers to threads. It
       takes responsibility of deallocating the threads. So we implement the
       destructor. */
    ~thread_group()
    {
      while (!tlist.empty())
        {
          delete tlist.front();
          tlist.pop_front();
        }
    }
    /* Here we run the threads ensuring that not more than
       |max_parallel_threads| are run in parallel. More over, we do not want
       to run a too low number of threads, since it is wasting with resource
       (if there are). Therefore, we run in parallel |max_parallel_threads|
       batches as long as the remaining threads are greater than the double
       number. And then the remaining batch (less than |2*max_parallel_threads|)
       is run half by half. */

    void
    run()
    {
      int rem = tlist.size();
      iterator pfirst = tlist.begin();
      while (rem > 2*max_parallel_threads)
        {
          pfirst = run_portion(pfirst, max_parallel_threads);
          rem -= max_parallel_threads;
        }
      if (rem > max_parallel_threads)
        {
          pfirst = run_portion(pfirst, rem/2);
          rem -= rem/2;
        }
      run_portion(pfirst, rem);
    }

  private:
    /* This runs a given number of threads in parallel starting from the
       given iterator. It returns the first iterator not run. */

    iterator
    run_portion(iterator start, int n)
    {
      int c = 0;
      for (iterator i = start; c < n; ++i, c++)
        {
          (*i)->run();
        }
      iterator ret;
      c = 0;
      for (ret = start; c < n; ++ret, c++)
        {
          _Ttraits::join(*ret);
        }
      return ret;
    }
  };


  /* Clear. We have only |init|, |lock|, and |unlock|. */
  struct ltmmkey;
  using mmkey = pair<const void *, const char *>;

  template <int thread_impl>
  struct mutex_traits
  {
    using _Tmutex = std::conditional_t<thread_impl == posix, pthread_mutex_t, Empty>;
    using mutex_int_map = map<mmkey, pair<_Tmutex, int>, ltmmkey>;
    static void init(_Tmutex &m);
    static void lock(_Tmutex &m);
    static void unlock(_Tmutex &m);
  };

  /* Here we define a map of mutexes keyed by a pair of address, and a
     string. A purpose of the map of mutexes is that, if synchronizing, we
     need to publish mutexes locking some piece of codes (characterized by
     the string) accessing the data (characterized by the pointer). So, if
     any thread needs to pass a |synchro| object, it creates its own with
     the same address and string, and must look to some public storage to
     unlock the mutex. If the |synchro| object is created for the first
     time, the mutex is created and inserted to the map. We count the
     references to the mutex (number of waiting threads) to know, when it
     is save to remove the mutex from the map. This is the only purpose of
     counting the references. Recall, that the mutex is keyed by an address
     of the data, and without removing, the number of mutexes would only
     grow.

     The map itself needs its own mutex to avoid concurrent insertions and
     deletions. */

  struct ltmmkey
  {
    bool
    operator()(const mmkey &k1, const mmkey &k2) const
    {
      return k1.first < k2.first
                        || (k1.first == k2.first && strcmp(k1.second, k2.second) < 0);
    }
  };

  template <int thread_impl>
  class mutex_map :
    public mutex_traits<thread_impl>::mutex_int_map
  {
    using _Tmutex = typename mutex_traits<thread_impl>::_Tmutex;
    using _Mtraits = mutex_traits<thread_impl>;
    using mmval = pair<_Tmutex, int>;
    using _Tparent = map<mmkey, mmval, ltmmkey>;
    using iterator = typename _Tparent::iterator;
    using _mvtype = typename _Tparent::value_type;
    _Tmutex m;
  public:
    mutex_map()
    {
      _Mtraits::init(m);
    }
    void
    insert(const void *c, const char *id, const _Tmutex &m)
    {
      _Tparent::insert(_mvtype(mmkey(c, id), mmval(m, 0)));
    }
    bool
    check(const void *c, const char *id) const
    {
      return _Tparent::find(mmkey(c, id)) != _Tparent::end();
    }
    /* This returns a pointer to the pair of mutex and count reference number. */
    mmval *
    get(const void *c, const char *id)
    {
      auto it = _Tparent::find(mmkey(c, id));
      if (it == _Tparent::end())
        return nullptr;
      return &((*it).second);
    }

    /* This removes unconditionally the mutex from the map regardless its
       number of references. The only user of this class should be |synchro|
       class, it implementation must not remove referenced mutex. */

    void
    remove(const void *c, const char *id)
    {
      auto it = _Tparent::find(mmkey(c, id));
      if (it != _Tparent::end())
        this->erase(it);
    }
    void
    lock_map()
    {
      _Mtraits::lock(m);
    }
    void
    unlock_map()
    {
      _Mtraits::unlock(m);
    }

  };

  /* This is the |synchro| class. The constructor of this class tries to
     lock a mutex for a particular address (identification of data) and
     string (identification of entry-point). If the mutex is already
     locked, it waits until it is unlocked and then returns. The destructor
     releases the lock. The typical use is to construct the object on the
     stacked of the code being synchronized. */

  template <int thread_impl>
  class synchro
  {
    using _Tmutex = typename mutex_traits<thread_impl>::_Tmutex;
    using _Mtraits = mutex_traits<0>;
  public:
    using mutex_map_t = mutex_map<0>;
  private:
    const void *caller;
    const char *iden;
    mutex_map_t &mutmap;
  public:
    synchro(const void *c, const char *id, mutex_map_t &mmap)
      : caller(c), iden(id), mutmap(mmap)
    {
      lock();
    }
    ~synchro()
    {
      unlock();
    }
  private:
    /* The |lock| function acquires the mutex in the map. First it tries to
       get an exclusive access to the map. Then it increases a number of
       references of the mutex (if it does not exists, it inserts it). Then
       unlocks the map, and finally tries to lock the mutex of the map. */

    void
    lock()
    {
      mutmap.lock_map();
      if (!mutmap.check(caller, iden))
        {
          _Tmutex mut;
          _Mtraits::init(mut);
          mutmap.insert(caller, iden, mut);
        }
      mutmap.get(caller, iden)->second++;
      mutmap.unlock_map();
      _Mtraits::lock(mutmap.get(caller, iden)->first);
    }

    /* The |unlock| function first locks the map. Then releases the lock,
       and decreases a number of references. If it is zero, it removes the
       mutex. */

    void
    unlock()
    {
      mutmap.lock_map();
      if (mutmap.check(caller, iden))
        {
          _Mtraits::unlock(mutmap.get(caller, iden)->first);
          mutmap.get(caller, iden)->second--;
          if (mutmap.get(caller, iden)->second == 0)
            mutmap.remove(caller, iden);
        }
      mutmap.unlock_map();
    }
  };

  /* These are traits for conditions. We need |init|, |broadcast|, |wait|
     and |destroy|. */

  template <int thread_impl>
  struct cond_traits
  {
    using _Tcond = std::conditional_t<thread_impl == posix, pthread_cond_t, Empty>;
    using _Tmutex = typename mutex_traits<thread_impl>::_Tmutex;
    static void init(_Tcond &cond);
    static void broadcast(_Tcond &cond);
    static void wait(_Tcond &cond, _Tmutex &mutex);
    static void destroy(_Tcond &cond);
  };

  /* Here is the condition counter. It is a counter which starts at 0,
     and can be increased and decreased. A thread can wait until the
     counter is changed, this is implemented by condition. After the wait
     is done, another (or the same) thread, by calling |waitForChange|
     waits for another change. This can be dangerous, since it is possible
     to wait for a change which will not happen, because all the threads
     which can cause the change (by increase of decrease) might had
     finished. */

  template <int thread_impl>
  class condition_counter
  {
    using _Tmutex = typename mutex_traits<thread_impl>::_Tmutex;
    using _Tcond = typename cond_traits<thread_impl>::_Tcond;
    int counter{0};
    _Tmutex mut;
    _Tcond cond;
    bool changed{true};
  public:
    /* We initialize the counter to 0, and |changed| flag to |true|, since
       the counter was change from undefined value to 0. */

    condition_counter()
       
    {
      mutex_traits<thread_impl>::init(mut);
      cond_traits<thread_impl>::init(cond);
    }

    /* In destructor, we only release the resources associated with the
       condition. */

    ~condition_counter()
    {
      cond_traits<thread_impl>::destroy(cond);
    }

    /* When increasing, we lock the mutex, advance the counter, remember it
       is changed, broadcast, and release the mutex. */

    void
    increase()
    {
      mutex_traits<thread_impl>::lock(mut);
      counter++;
      changed = true;
      cond_traits<thread_impl>::broadcast(cond);
      mutex_traits<thread_impl>::unlock(mut);
    }

    /* Same as increase. */
    void
    decrease()
    {
      mutex_traits<thread_impl>::lock(mut);
      counter--;
      changed = true;
      cond_traits<thread_impl>::broadcast(cond);
      mutex_traits<thread_impl>::unlock(mut);
    }

    /* We lock the mutex, and if there was a change since the last call of
       |waitForChange|, we return immediately, otherwise we wait for the
       change. The mutex is released. */

    int
    waitForChange()
    {
      mutex_traits<thread_impl>::lock(mut);
      if (!changed)
        {
          cond_traits<thread_impl>::wait(cond, mut);
        }
      changed = false;
      int res = counter;
      mutex_traits<thread_impl>::unlock(mut);
      return res;
    }
  };

  /* The detached thread is the same as joinable |thread|. We only
     re-implement |run| method to call |thread_traits::detach_run|, and add
     a method which installs a counter. The counter is increased and
     decreased on the body of the new thread. */

  template <int thread_impl>
  class detach_thread : public thread<thread_impl>
  {
  public:
    condition_counter<thread_impl> *counter;
    detach_thread() : counter(nullptr)
    {
    }
    void
    installCounter(condition_counter<thread_impl> *c)
    {
      counter = c;
    }
    void
    run()
    {
      thread_traits<thread_impl>::detach_run(this);
    }
  };

  /* The detach thread group is (by interface) the same as
     |thread_group|. The extra thing we have here is the |counter|. The
     implementation of |insert| and |run| is different. */

  template<int thread_impl>
  class detach_thread_group
  {
    using _Ttraits = thread_traits<thread_impl>;
    using _Ctraits = cond_traits<thread_impl>;
    using _Ctype = detach_thread<thread_impl>;
    list<unique_ptr<_Ctype>> tlist;
    using iterator = typename list<unique_ptr<_Ctype>>::iterator;
    condition_counter<thread_impl> counter;
  public:
    static int max_parallel_threads;

    /* When inserting, the counter is installed to the thread. */
    void
    insert(unique_ptr<_Ctype> c)
    {
      c->installCounter(&counter);
      tlist.push_back(move(c));
    }

    ~detach_thread_group() = default;

    /* We cycle through all threads in the group, and in each cycle we wait
       for the change in the |counter|. If the counter indicates less than
       maximum parallel threads running, then a new thread is run, and the
       iterator in the list is moved.

       At the end we have to wait for all thread to finish. */

    void
    run()
    {
      int mpt = max_parallel_threads;
      auto it = tlist.begin();
      while (it != tlist.end())
        {
          if (counter.waitForChange() < mpt)
            {
              counter.increase();
              (*it)->run();
              ++it;
            }
        }
      while (counter.waitForChange() > 0)
        {
        }
    }
  };

#ifdef HAVE_PTHREAD
  // POSIX thread specializations
  /* Here we only define the specializations for POSIX threads. Then we
     define the macros. Note that the |PosixSynchro| class construct itself
     from the static map defined in {\tt sthreads.cpp}. */
  using PosixThread = detach_thread<posix>;
  using PosixThreadGroup = detach_thread_group<posix>;
  using posix_synchro = synchro<posix>;
  class PosixSynchro : public posix_synchro
  {
  public:
    PosixSynchro(const void *c, const char *id);
  };

# define THREAD sthread::PosixThread
# define THREAD_GROUP sthread::PosixThreadGroup
# define SYNCHRO sthread::PosixSynchro

#else
  // No threading specializations@>=
  /* Here we define an empty class and use it as thread and
     mutex. |NoSynchro| class is also empty, but an empty constructor is
     declared. The empty destructor is declared only to avoid ``unused
     variable warning''. */
  using NoThread = thread<empty>;
  using NoThreadGroup = thread_group<empty>;
  using no_synchro = synchro<empty>;
  class NoSynchro
  {
  public:
    NoSynchro(const void *c, const char *id)
    {
    }
    ~NoSynchro()
    {
    }
  };

# define THREAD sthread::NoThread
# define THREAD_GROUP sthread::NoThreadGroup
# define SYNCHRO sthread::NoSynchro

#endif
};

#endif
